#include "sys.h"
#include "util.h"
#include "syscqct.h"
#include "x/include/fmt.h"

Xfd l1stdin, l1stdout, l1stderr;

void
xfdclose(Xfd *xfd)
{
	close(xfd->fd);
}

Imm
xfdread(Xfd *xfd, char *buf, Imm len)
{
	return read(xfd->fd, buf, len);
}

Imm
xfdwrite(Xfd *xfd, char *buf, Imm len)
{
	Imm rv;
	rv = xwrite(xfd->fd, buf, len);
	return rv;
}

static int
xfdflush(Fmt *f)
{
	Imm n, rv;
	Xfd *xfd;
	n = (char*)f->to-(char*)f->start;
	xfd = (Xfd*)f->farg;
	rv = xfd->write(xfd, f->start, n);
	if(rv == -1)
		return 0;
	f->to = f->start;
	return 1;
}

static void
xfdfmtinit(Fmt *f, Xfd *xfd, char *buf, int size)
{
	f->runes = 0;
	f->start = buf;
	f->to = buf;
	f->stop = buf + size;
	f->flush = xfdflush;
	f->farg = (void*)xfd;
	f->flags = 0;
	f->nfmt = 0;
	fmtlocaleinit(f, 0, 0, 0);
}

void
cvprintf(Xfd *xfd, char *fmt, va_list args)
{
	struct Fmt f;
	char buf[256];

	if(!xfd->write)
		return;
	xfdfmtinit(&f, xfd, buf, sizeof(buf));
	fmtvprint(&f, fmt, args);
	xfdflush(&f);
}

void
cprintf(Xfd *xfd, char *fmt, ...)
{
	va_list args;
	va_start(args, fmt);
	cvprintf(xfd, fmt, args);
	va_end(args);
}

void
finiio()
{
}

void
initio(const Xfd *in, const Xfd *out, const Xfd *err)
{
	if(!in || !out || !err)
		bug();
	l1stdin = *in;
	l1stdout = *out;
	l1stderr = *err;
#ifdef L1_HAVE_XFD
	REGFN(xfdclose);
	REGFN(xfdread);
	REGFN(xfdwrite);
#endif // L1_HAVE_XFD
}
