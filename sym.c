#include "sys.h"
#include "util.h"
#include "syscqct.h"

Val
mkattr(Val o)
{
	Tab *tab;

	if(!Viskind(o, Qtab) && !Viskind(o, Qcval) && !Viskind(o, Qnil))
		fatal("bug");
	if(Viskind(o, Qtab))
		tab = tabcopy(valtab(o));
	else if(Viskind(o, Qnil))
		tab = mktab();
	else{
		tab = mktab();
		tabput(tab, mkvalcid(mkcid0("offset")), o);
	}
	return mkvaltab(tab);
}

Val
attroff(Val o)
{
	Tab *tab;
	Val vp;

	if(Viskind(o, Qcval))
		return o;
	if(!Viskind(o, Qtab))
		fatal("bug");
	tab = valtab(o);
	vp = tabget(tab, mkvalcid(mkcid0("offset")));
	if(vp)
		return vp;
	return Xnil;
}

Val
copyattr(Val attr, Val newoff)
{
	Tab *t;
	Val off;
	Val key;
	if(!Viskind(attr, Qtab))
		fatal("bug");
	t = tabcopy(valtab(attr));
	key = mkvalcid(mkcid0("offset"));
	if(newoff)
		off = newoff;
	else
		off = tabget(t, key);
	tabput(t, key, off);
	return mkvaltab(t);
}

Ctype*
fieldtype(Vec *s)
{
	Val v;
	v = vecref(s, Typepos);
	if(!Viskind(v, Qctype))
		bug();
	return valctype(v);
}

Ctype*
paramtype(Vec *s)
{
	Val v;
	v = vecref(s, Typepos);
	if(!Viskind(v, Qctype))
		bug();
	return valctype(v);
}

Ctype*
symtype(Vec *s)
{
	Val v;
	v = vecref(s, Typepos);
	if(!Viskind(v, Qctype))
		bug();
	return valctype(v);
}

int
issym(Vec *sym)
{
	Val x;

	if(sym->len != 2 && sym->len != 3)
		return 0;
	x = vecref(sym, Typepos);
	if(!Viskind(x, Qctype))
		return 0;
	x = vecref(sym, Idpos);
	if(!Viskind(x, Qcid) && !Viskind(x, Qnil))
		return 0;
	if(sym->len < 3)
		return 1;
	x = vecref(sym, Attrpos);
	if(!Viskind(x, Qtab) && !Viskind(x, Qnil))
		return 0;
	return 1;
}

int
issymvec(Vec *v)
{
	Imm m;
	Val e;
	Vec *sym;
	for(m = 0; m < v->len; m++){
		e = vecref(v, m);
		if(!Viskind(e, Qvec))
			return 0;
		sym = valvec(e);
		if(!issym(sym))
			return 0;
	}
	return 1;
}

static void
mksymorfieldorparam(char *what, VM *vm, Imm argc, Val *argv, Val *rv)
{
	Vec *vec;
	Val attr;

	checkarg(vm, argv, 0, Qctype);
	if(argc > 1)
		if(!Viskind(argv[1], Qcid) && !Viskind(argv[1], Qnil))
			vmerr(vm, "operand 2 to %s must be "
			      "an identifier or nil",
			      what);
	if(argc == 3)
		if(!Viskind(argv[2], Qcval)
		   && !Viskind(argv[2], Qtab)
		   && !Viskind(argv[2], Qnil))
			vmerr(vm,
			      "operand 3 to %s must be a table, cvalue, or nil",
			      what);
	vec = mkvec(3);
	_vecset(vec, Typepos, argv[0]);
	if(argc > 1)
		_vecset(vec, Idpos, argv[1]);
	else
		_vecset(vec, Idpos, Xnil);
	if(argc > 2 && Viskind(argv[2], Qcval))
		attr = mkattr(argv[2]);
	else if(argc > 2)
		attr = argv[2];
	else
		attr = Xnil;
	_vecset(vec, Attrpos, attr);
	*rv = mkvalvec(vec);
}

static void
l1_mksym(VM *vm, Imm argc, Val *argv, Val *rv)
{
	if(argc != 2 && argc != 3)
		vmerr(vm, "wrong number of arguments to mksym");
	mksymorfieldorparam("mksym", vm, argc, argv, rv);
}

static void
l1_mkfield(VM *vm, Imm argc, Val *argv, Val *rv)
{
	if(argc != 2 && argc != 3)
		vmerr(vm, "wrong number of arguments to mkfield");
	mksymorfieldorparam("mkfield", vm, argc, argv, rv);
}

static void
l1_mkparam(VM *vm, Imm argc, Val *argv, Val *rv)
{
	if(argc < 1 || argc > 3)
		vmerr(vm, "wrong number of arguments to mkparam");
	mksymorfieldorparam("mkparam", vm, argc, argv, rv);
}

static void
l1_paramtype(VM *vm, Imm argc, Val *argv, Val *rv)
{
	Vec *v;
	Val vp;
	static char *err
		= "operand 1 to paramtype must be a param";

	if(argc != 1)
		vmerr(vm, "wrong number of arguments to paramtype");
	if(!Viskind(argv[0], Qvec))
		vmerr(vm, err);
	v = valvec(argv[0]);
	if(v->len < 2)
		vmerr(vm, err);
	vp = vecdata(v)[Typepos];
	if(!Viskind(vp, Qctype))
		vmerr(vm, err);
	*rv = vp;
}

static void
l1_paramid(VM *vm, Imm argc, Val *argv, Val *rv)
{
	Vec *v;
	Val vp;
	static char *err
		= "operand 1 to paramid must be a param";

	if(argc != 1)
		vmerr(vm, "wrong number of arguments to paramid");
	if(!Viskind(argv[0], Qvec))
		vmerr(vm, err);
	v = valvec(argv[0]);
	if(v->len < 2)
		vmerr(vm, err);
	vp = vecdata(v)[Idpos];
	if(!Viskind(vp, Qcid) && !Viskind(vp, Qnil))
		vmerr(vm, err);
	*rv = vp;
}

static void
l1_paramattr(VM *vm, Imm argc, Val *argv, Val *rv)
{
	Vec *v;
	static char *err
		= "operand 1 to paramattr must be a param";

	if(argc != 1)
		vmerr(vm, "wrong number of arguments to paramattr");
	if(!Viskind(argv[0], Qvec))
		vmerr(vm, err);
	v = valvec(argv[0]);
	if(v->len < 3)
		return; /* nil */
	*rv = vecref(v, Attrpos);
}

static void
l1_fieldtype(VM *vm, Imm argc, Val *argv, Val *rv)
{
	Vec *v;
	Val vp;
	static char *err
		= "operand 1 to fieldtype must be a field";

	if(argc != 1)
		vmerr(vm, "wrong number of arguments to fieldtype");
	if(!Viskind(argv[0], Qvec))
		vmerr(vm, err);
	v = valvec(argv[0]);
	if(v->len < 3)
		vmerr(vm, err);
	vp = vecdata(v)[Typepos];
	if(!Viskind(vp, Qctype))
		vmerr(vm, err);
	*rv = vp;
}

static void
l1_fieldid(VM *vm, Imm argc, Val *argv, Val *rv)
{
	Vec *v;
	Val vp;
	static char *err
		= "operand 1 to fieldid must be a field";

	if(argc != 1)
		vmerr(vm, "wrong number of arguments to fieldid");
	if(!Viskind(argv[0], Qvec))
		vmerr(vm, err);
	v = valvec(argv[0]);
	if(v->len < 3)
		vmerr(vm, err);
	vp = vecdata(v)[Idpos];
	if(!Viskind(vp, Qcid) && !Viskind(vp, Qnil))
		vmerr(vm, err);
	*rv = vp;
}

static void
l1_fieldattr(VM *vm, Imm argc, Val *argv, Val *rv)
{
	Vec *v;
	static char *err
		= "operand 1 to fieldattr must be a field";

	if(argc != 1)
		vmerr(vm, "wrong number of arguments to fieldattr");
	if(!Viskind(argv[0], Qvec))
		vmerr(vm, err);
	v = valvec(argv[0]);
	if(v->len < 3)
		vmerr(vm, err);
	*rv = vecref(v, Attrpos);
}

static void
l1_fieldoff(VM *vm, Imm argc, Val *argv, Val *rv)
{
	Vec *v;
	Val vp;
	static char *err
		= "operand 1 to fieldoff must be a field";

	if(argc != 1)
		vmerr(vm, "wrong number of arguments to fieldoff");
	if(!Viskind(argv[0], Qvec))
		vmerr(vm, err);
	v = valvec(argv[0]);
	if(v->len < 3)
		vmerr(vm, err);
	vp = vecref(v, Attrpos);
	if(Viskind(vp, Qnil))
		return;		/* nil */
	vp = attroff(vp);
	*rv  = vp;
}

static void
l1_symtype(VM *vm, Imm argc, Val *argv, Val *rv)
{
	Vec *v;
	Val vp;
	static char *err
		= "operand 1 to symtype must be a symbol";

	if(argc != 1)
		vmerr(vm, "wrong number of arguments to symtype");
	if(!Viskind(argv[0], Qvec))
		vmerr(vm, err);
	v = valvec(argv[0]);
	if(v->len < 3)
		vmerr(vm, err);
	vp = vecdata(v)[Typepos];
	if(!Viskind(vp, Qctype))
		vmerr(vm, err);
	*rv = vp;
}

static void
l1_symid(VM *vm, Imm argc, Val *argv, Val *rv)
{
	Vec *v;
	Val vp;
	static char *err
		= "operand 1 to symid must be a symbol";

	if(argc != 1)
		vmerr(vm, "wrong number of arguments to symid");
	if(!Viskind(argv[0], Qvec))
		vmerr(vm, err);
	v = valvec(argv[0]);
	if(v->len < 3)
		vmerr(vm, err);
	vp = vecdata(v)[Idpos];
	if(!Viskind(vp, Qcid) && !Viskind(vp, Qnil))
		vmerr(vm, err);
	*rv = vp;
}

static void
l1_symattr(VM *vm, Imm argc, Val *argv, Val *rv)
{
	Vec *v;
	static char *err
		= "operand 1 to symattr must be a symbol";

	if(argc != 1)
		vmerr(vm, "wrong number of arguments to symattr");
	if(!Viskind(argv[0], Qvec))
		vmerr(vm, err);
	v = valvec(argv[0]);
	if(v->len < 3)
		vmerr(vm, err);
	*rv = vecref(v, Attrpos);
}

static void
l1_symoff(VM *vm, Imm argc, Val *argv, Val *rv)
{
	Vec *v;
	Val vp;
	static char *err
		= "operand 1 to symoff must be a symbol";

	if(argc != 1)
		vmerr(vm, "wrong number of arguments to symoff");
	if(!Viskind(argv[0], Qvec))
		vmerr(vm, err);
	v = valvec(argv[0]);
	if(v->len < 3)
		vmerr(vm, err);
	vp = vecref(v, Attrpos);
	if(Viskind(vp, Qnil))
		return;		/* nil */
	*rv = attroff(vp);
}

void
fnsym(Env env)
{
	FN(fieldattr);
	FN(fieldid);
	FN(fieldoff);
	FN(fieldtype);
	FN(mkfield);
	FN(mkparam);
	FN(mksym);
	FN(paramattr);
	FN(paramid);
	FN(paramtype);
	FN(symattr);
	FN(symid);
	FN(symoff);
	FN(symtype);
}
