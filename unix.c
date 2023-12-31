#include "sys.h"
#include "util.h"
#include "syscqct.h"

char sysarch[256];
char sysos[256];

Imm
xread(int fd, char *p, Imm len)
{
	Imm nr;
	ssize_t rv;

	nr = 0;
	while(nr < len){
		rv = read(fd, p, len-nr);
		if(0 > rv)
			return -1;
		if(0 == rv)
			return nr;
		nr += rv;
		p += rv;
	}
	return nr;
}

char*
readfile(char *filename)
{
	char *buf;
	struct stat st;
	int fd;

	if(0 > stat(filename, &st))
		return 0;
	if(!S_ISREG(st.st_mode))
		return 0;
	fd = open(filename, O_RDONLY);
	if(0 > fd)
		return 0;
	buf = emalloc(st.st_size+1);
	if(-1 == xread(fd, buf, st.st_size)){
		efree(buf);
		close(fd);
		return 0;
	}
	close(fd);
	return buf;
}

Imm
xwrite(int fd, void *p, Imm len)
{
	Imm ns;
	ssize_t rv;

	ns = 0;
	while(ns < len){
		rv = write(fd, p, len-ns);
		if(0 > rv){
			printf("xwrite returning error\n");
			return -1;
		}
		ns += rv;
		p += rv;
	}
	return ns;
}

void
xvprintf(char *fmt, va_list args)
{
	cvprintf(&l1stdout, fmt, args);
}

void
xprintf(char *fmt, ...)
{
	va_list args;
	va_start(args, fmt);
	xvprintf(fmt, args);
	va_end(args);
}

void
xabort()
{
	abort();
}

static int
newchan(int *left, int *right)
{
	int fd[2];

	if(0 > socketpair(PF_UNIX, SOCK_STREAM, 0, fd))
		return -1;
	*left = fd[0];
	*right = fd[1];
	return 0;
}

void
setproftimer(u32 usec, void(*fn)())
{
	struct itimerval it;
	memset(&it, 0, sizeof(it));
	it.it_interval.tv_usec = usec;
	it.it_value.tv_usec = usec;
	if(fn)
		signal(SIGPROF, fn);
	if(0 > setitimer(ITIMER_PROF, &it, 0))
		fatal("setitimer: %s", strerror(errno));
	if(fn == 0)
		signal(SIGPROF, SIG_DFL);
}

static void
cloexec(int fd)
{
	int f;
	f = fcntl(fd, F_GETFD);
	if(f == -1)
		fatal("fcntl: %s", strerror(errno));
	f |= FD_CLOEXEC;
	if(fcntl(fd, F_SETFD, f))
		fatal("fcntl: %s", strerror(errno));
}

int
xpopen(Imm argc, char **argv, unsigned flags, int *rfd)
{
	int ctl[2], in[2], out[2], err[2];
	Imm rv;
	int pid, eno, i, m;

	/* ignore sigpipe from now on */
	signal(SIGPIPE, SIG_IGN);

	if(0 > newchan(&ctl[0], &ctl[1]))
		return -errno;
	if(0 > newchan(&in[0], &in[1]))
		return -errno;
	if(flags&PopenFullDuplex){
		out[0] = in[0];
		out[1] = in[1];
	}else
		if(0 > newchan(&out[0], &out[1]))
			return -errno;
	if(flags&PopenStderr)
		err[0] = err[1] = -1;
	else if(flags&PopenNoErr)
		err[0] = err[1] = -1;
	else
		if(0 > newchan(&err[0], &err[1]))
			return -errno;
	cloexec(ctl[1]);
	switch(pid = fork()){
	case 0:
		switch(fork()){
		case 0:
			close(in[0]);
			close(out[0]);
			close(err[0]);
			close(ctl[0]);
			dup2(in[1], 0);
			if(flags&PopenStdout)
				out[1] = 1;
			dup2(out[1], 1);
			if(flags&PopenNoErr)
				err[1] = open("/dev/null", O_WRONLY);
			else if(flags&PopenStderr)
				err[1] = 2;
			dup2(err[1], 2);
			if(in[1] > 2)
				close(in[1]);
			if(out[1] > 2)
				close(out[1]);
			if(err[1] > 2)
				close(err[1]);
			m = sysconf(_SC_OPEN_MAX);
			for(i = 3; i < m; i++)
				if(i != ctl[1])
					close(i);
			if(flags&PopenSession)
				setsid();
			execvp(argv[0], argv);
			eno = errno;
			xwrite(ctl[1], &eno, sizeof(eno));
			_exit(1);
		case -1:
			eno = errno;
			xwrite(ctl[1], &eno, sizeof(eno));
			_exit(1);
		default:
			_exit(0);
		}
	case -1:
		return -errno;
	default:
		close(in[1]);
		close(out[1]);
		close(err[1]);
		close(ctl[1]);
		waitpid(pid, 0, 0);
		rv = xread(ctl[0], (char*)&eno, sizeof(eno));
		close(ctl[0]);
		if(rv == 0){
			rfd[0] = in[0];
			rfd[1] = out[0];
			if((flags&(PopenNoErr|PopenStderr)) == 0)
				rfd[2] = err[0];
			return 0;
		}
		if(rv == -1)
			fatal("popen: cannot communicate with child: %s",
			      strerror(errno));
		/* child exec failed */
		close(in[0]);
		close(out[0]);
		close(err[0]);
		return -eno; /* -errno of child */
	}
}

int
xmunmap(void *p, Imm len)
{
	return munmap(p, (size_t)len);
}

Imm
usec(void)
{
	Imm u;
	struct timeval tv;
	gettimeofday(&tv, 0);
	u = tv.tv_sec;
	u *= 1000000;
	u += tv.tv_usec;
	return u;
}

static void
stolower(char *s)
{
	unsigned i, m;
	m = strlen(s);
	for(i = 0; i < m; i++)
		s[i] = tolower(s[i]);
}

void
initos()
{
	struct utsname buf;
	if(0 > uname(&buf))
		fatal("no uname");
	if((getuid() == geteuid()) && getenv("L1ARCH")) {
		strncpy(sysarch, getenv("L1ARCH"), sizeof(sysarch)-1);
	}
	if(!sysarch[0]) {
		strncpy(sysarch, buf.machine, sizeof(sysarch)-1);
		if(strcmp(sysarch, "x86_64") == 0)
			strcpy(sysarch, "amd64");
		if((strcmp(sysarch, "amd64") == 0) && (sizeof(long) == 4))
			strcpy(sysarch, "i686");
	}
	if((getuid() == geteuid()) && getenv("L1OS")) {
		strncpy(sysos, getenv("L1OS"), sizeof(sysos)-1);
	}
	if(!sysos[0]) {
		strncpy(sysos, buf.sysname, sizeof(sysos)-1);
	}
	stolower(sysarch);
	stolower(sysos);
}
