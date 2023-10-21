#include "sys.h"
#include "util.h"
#include "syscqct.h"

#ifdef L1_C_READDIR
static void
l1__readdir(VM *vm, Imm argc, Val *argv, Val *rv)
{
	DIR *dir;
	Str *names;
	char *name;
	u32 ndir, lim;
	char *buf;
	struct dirent *p, *d;

	if(argc != 1)
		vmerr(vm, "wrong number of arguments to readdir");
	checkarg(vm, argv, 0, Qstr);
	names = valstr(argv[0]);
	name = str2cstr(names);
	dir = opendir(name);
	efree(name);
	if(dir == 0)
		vmerr(vm, "opendir: %s", strerror(errno));

	lim = 128;
	buf = emalloc(lim*sizeof(struct dirent));
	ndir = 0;
	p = (struct dirent*)buf;
	while((d = readdir(dir))) {
		if(ndir >= lim) {
			buf = erealloc(buf, lim*sizeof(struct dirent),
				       2*lim*sizeof(struct dirent));
			lim *= 2;
			p = (struct dirent*)buf+ndir;
		}
		memcpy(p, d, d->d_reclen);
		p++;
		ndir++;
	}
	closedir(dir);
	*rv = mkvalas(mksas(mkstr(buf, ndir*sizeof(struct dirent))));
	efree(buf);
}
#endif // L1_C_READDIR

#ifdef L1_C_MKDIR
static void
l1_mkdir(VM *vm, Imm argc, Val *argv, Val *rv)
{
	Str *names;
	char *name;
	int r;

	setlasterrno(0);

	if(argc != 1)
		vmerr(vm, "wrong number of arguments to mkdir");
	checkarg(vm, argv, 0, Qstr);
	names = valstr(argv[0]);
	name = str2cstr(names);
	r = mkdir(name, 0777);	/* ~umask */
	efree(name);
	if(0 > r)
		setlasterrno(errno);

        *rv = mkvallitcval(Vint, r);
}
#endif // L1_C_MKDIR

#ifdef L1_C_UNLINK
static void
l1_unlink(VM *vm, Imm argc, Val *argv, Val *rv)
{
	Str *names;
	char *name;
	int r;

	setlasterrno(0);

	if(argc != 1)
		vmerr(vm, "wrong number of arguments to unlink");
	checkarg(vm, argv, 0, Qstr);
	names = valstr(argv[0]);
	name = str2cstr(names);
	r = unlink(name);
	efree(name);
	if(0 > r)
		setlasterrno(errno);

        *rv = mkvallitcval(Vint, r);
}
#endif // L1_C_UNLINK

#ifdef L1_C_RMDIR
static void
l1_rmdir(VM *vm, Imm argc, Val *argv, Val *rv)
{
	Str *names;
	char *name;
	int r;

	setlasterrno(0);

	if(argc != 1)
		vmerr(vm, "wrong number of arguments to rmdir");
	checkarg(vm, argv, 0, Qstr);
	names = valstr(argv[0]);
	name = str2cstr(names);
	r = rmdir(name);
	efree(name);
	if(0 > r)
		setlasterrno(errno);

        *rv = mkvallitcval(Vint, r);
}
#endif // L1_C_RMDIR

void
fnfs(Env env)
{
#ifdef L1_C_READDIR
	FN(_readdir);
#endif
#ifdef L1_C_MKDIR
	FN(mkdir);
#endif // L1_C_MKDIR
#ifdef L1_C_RMDIR
	FN(rmdir);
#endif // L1_C_RMDIR
#ifdef L1_C_UNLINK
	FN(unlink);
#endif // L1_C_UNLINK
}
