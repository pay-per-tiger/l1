#include "sys.h"
#include "util.h"
#include "syscqct.h"

char* cbasename[Vnbase+1] = {
	[Vundef]              = "error!",
	[Vbool]		      = "_Bool",
	[Vchar]               = "char",
	[Vshort]	      = "short",
	[Vint]		      = "int",
	[Vlong]		      = "long",
	[Vvlong]	      = "long long",
	[Vuchar]	      = "unsigned char",
	[Vushort]	      = "unsigned short",
	[Vuint]		      = "unsigned int",
	[Vulong]	      = "unsigned long",
	[Vuvlong]	      = "unsigned long long",
	[Vfloat]	      = "float",
	[Vdouble]	      = "double",
	[Vlongdouble]	      = "long double",
	[Vcomplex]	      = "float _Complex",
	[Vdoublex]            = "double _Complex",
	[Vlongdoublex]        = "long double _Complex",
	[Vptr]		      = "$nsptr",
};

char* tkindstr[Tntkind] = {
	[Tarr]			= "array",
	[Tbase]			= "base",
	[Tenum]			= "enum",
	[Tfun]			= "function",
	[Tptr]			= "pointer",
	[Tstruct]		= "struct",
	[Ttypedef]		= "typedef",
	[Tunion]		= "union",
	[Tvoid]			= "void",
	[Tbitfield]		= "bitfield",
	[Tconst]		= "constant",
	[Tundef]		= "undef",
};

static HT *filenames;

extern int yylex_destroy(void);

static const int k_errorbuf_size = 256;

void
parseerror(U *ctx, char *fmt, ...)
{
	va_list args;
	u32 len;

	if(ctx == 0){
		/*
		 * we're here because of a bison limitation.
		 * the caller is yyerror from one of our GLR merge
		 * resolvers, which do not convey %parse-params.
		 * abort because there is no way to recover.
		 */
		va_start(args, fmt);
		xvprintf(fmt, args);
		va_end(args);
		xprintf("\n");
		abort();
	}


	char *buf = emalloc(k_errorbuf_size);
	if(ctx->inp)
		snprintf(buf, k_errorbuf_size, "%s:%u:%u: ",
			 ctx->inp->src.filename,
			 ctx->inp->src.line,
			 ctx->inp->src.col);
	len = strlen(buf);
	va_start(args, fmt);
	vsnprint(buf+len, k_errorbuf_size-len, fmt, args);
	va_end(args);
	ctx->parse_error = buf;
}

Expr*
mkexpr()
{
	Val v;
	v = malv(Qexpr, sizeof(Expr));
	return (Expr*)v;
}

Expr*
newexprsrc(Ysrc *src, unsigned kind, Expr *e1, Expr *e2, Expr *e3, Expr *e4)
{
	Expr *e;
	Src s;

	e = mkexpr();
	e->kind = kind;
	e->skind = kind < Emax ? mkcid0(S[kind]) : 0;
	e->e1 = e1;
	e->e2 = e2;
	e->e3 = e3;
	e->e4 = e4;
	if(src){
		s = mksrc(src);
		putsrc(e, s);
	}
	return e;
}

Expr*
newexpr(unsigned kind, Expr *e1, Expr *e2, Expr *e3, Expr *e4)
{
	return newexprsrc(0, kind, e1, e2, e3, e4);
}

Expr*
newbinopsrc(Ysrc *src, unsigned kind, Expr *e1, Expr *e2)
{
	Expr *e;
	e = newexprsrc(src, kind, e1, e2, 0, 0);
	return e;
}

Expr*
newbinop(unsigned kind, Expr *e1, Expr *e2)
{
	return newbinopsrc(0, kind, e1, e2);
}

Expr*
newgopsrc(Ysrc *src, unsigned kind, Expr *e1, Expr *e2)
{
	Expr *e;
	e = newexprsrc(src, kind, e1, e2, 0, 0);
	return e;
}

/* intentionally does not copy e->xp */
Expr*
copyexpr(Expr *e)
{
	Expr *ne;

	if(e == 0)
		return 0;

	ne = mkexpr();
	ne->kind = e->kind;
	ne->skind = e->skind;
	ne->attr = e->attr;
	ne->src = e->src;
	switch(e->kind){
	case Eid:
	case Eval:
		ne->aux = e->aux;
		break;
	default:
		break;
	}

	ne->e1 = copyexpr(e->e1);
	ne->e2 = copyexpr(e->e2);
	ne->e3 = copyexpr(e->e3);
	ne->e4 = copyexpr(e->e4);
	return ne;
}

/* Reverse the order of elements in Eelist E.
   FIXME: is it better to cons a fresh list than update? */
Expr*
invert(Expr *e)
{
	Expr *tl, *q, *p, *t;

	if(e->kind == Enull)
		return e;

	tl = q = e;
	p = q->e2;
	while(p->kind != Enull){
		t = p->e2;
		sete2(p, q);
		q = p;
		p = t;
	}
	sete2(tl, p);

	return q;
}

/* Flatten Eelist of Eelists into single Eelist */
Expr*
flatten(Expr *e)
{
	Expr *p, *q;
	Expr *nl;

	nl = nullelist();
	p = e;
	while(p->kind != Enull){
		q = p->e1;
		while(q->kind != Enull){
			nl = newexpr(Eelist, q->e1, nl, 0, 0);
			q = q->e2;
		}
		p = p->e2;
	}
	putsrc(nl, e->src);
	nl = invert(nl);
	return nl;
}

Expr*
nullelistsrc(Ysrc *src)
{
	return newexprsrc(src, Enull, 0, 0, 0, 0);
}

Expr*
nullelist(void)
{
	return newexpr(Enull, 0, 0, 0, 0);
}

Expr*
ptrto(Expr *ptre, Expr *e)
{
	Expr *p;

	p = ptre;
	while(p->e1)
		p = p->e1;
	sete1(p, e);

	return ptre;
}

enum{
	Rany = 0,
	Rbin = 2,
	Roct = 8,
	Rhex = 16,
};

int
parselit(char *s, unsigned long len, Lit *lit, unsigned radix, char **err)
{
	Imm n;
	enum { Snone=0, Su, Sl, Sul, Sll, Sull, Sk, Sm, Sg, St } suf;
	unsigned base, noct;
	char c, *p, *z;
	char buf[Maxlit];	/* stage for null-terminated strtoull input */

	if(len >= Maxlit){
		*err = "excessively long literal";
		return -1;
	}

	memcpy(buf, s, len);
	buf[len] = 0;
	s = buf;
	z = s+len;

	if(s[0] == 'L'){
		*err = "wide characters unsupported";
		return -1;
	}

	/* char constant */
	if(s[0] == '\''){
		if(s[1] != '\\'){
			c = s[1];
			goto achar;
		}

		switch(s[2]){
		case 'n':
			c = '\n';
			break;
		case 't':
			c = '\t';
			break;
		case 'v':
			c = '\v';
			break;
		case 'b':
			c = '\b';
			break;
		case 'r':
			c = '\r';
			break;
		case 'f':
			c = '\f';
			break;
		case 'a':
			c = '\a';
			break;
		case '\\':
			c = '\\';
			break;
		case '\?':
			c = '\?';
			break;
		case '\'':
			c = '\'';
			break;
		case '"':
			c = '\"';
			break;
		default:
			p = &s[2];
			c = 0;
			if(*p == 'x'){
				p++;
				while(xisxdigit(*p)){
					c *= 16;
					if(xisdigit(*p))
						c += *p - '0';
					else if('a' <= *p && *p <= 'f')
						c += *p - 'a' + 10;
					else
						c += *p - 'A' + 10;
					p++;
				}
			}else{
				noct = 0;
				while(noct < 3 && xisodigit(*p)){
					c *= 8;
					c += *p - '0';
					p++;
					noct++;
				}
			}
			break;
		}
	achar:
		lit->base = Vchar;
		lit->v.u = c;
		return 0;
	}

	if(strnchr(s, '.', len)){
		lit->base = Vdouble;
		lit->v.d = strtod(s, 0);
		return 0;
	}

	/* caller must handle negative literals */
	if(strnchr(s, '-', len)){
		*err = "invalid integer constant";
		return -1;
	}

	/* integer constant */
	if(radix == Rany){
		if(s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
			radix = Rhex;
		else if(s[0] == '0' && (s[1] == 'b' || s[1] == 'B')){
			radix = Rbin;
			s += 2;
		}else if(s[0] == '0')
			radix = Roct;
	}
	n = strtoull(s, &p, radix);

	suf = Snone;
	if(p == s){
		*err = "invalid integer constant";
		return -1;
	}
	while(p < z){
		if(*p == 'U' || *p == 'u')
			switch(suf){
			case Snone:
				suf = Su;
				break;
			case Sl:
				suf = Sul;
				break;
			case Sll:
				suf = Sull;
				break;
			default:
				*err = "invalid use of constant suffix U";
				return -1;
			}
		else if(*p == 'L' || *p == 'l')
			switch(suf){
			case Snone:
				suf = Sl;
				break;
			case Sl:
				suf = Sll;
				break;
			case Su:
				suf = Sul;
				break;
			case Sul:
				suf = Sull;
				break;
			default:
				*err = "invalid use of constant suffix L";
				return -1;
			}
		else if(*p == 'K' || *p == 'k')
			switch(suf){
			case Snone:
				suf = Sk;
				break;
			default:
				*err = "invalid use of constant suffix K";
				return -1;
			}
		else if(*p == 'M' || *p == 'm')
			switch(suf){
			case Snone:
				suf = Sm;
				break;
			default:
				*err = "invalid use of constant suffix M";
				return -1;
			}
		else if(*p == 'G' || *p == 'g')
			switch(suf){
			case Snone:
				suf = Sg;
				break;
			default:
				*err = "invalid use of constant suffix G";
				return -1;
			}
		else if(*p == 'T' || *p == 't')
			switch(suf){
			case Snone:
				suf = St;
				break;
			default:
				*err = "invalid use of constant suffix T";
				return -1;
			}
		else{
			*err = "invalid integer constant";
			return -1;
		}
		p++;
	}

	base = Vundef;
	if((radix == Rbin || radix == Roct || radix == Rhex) && suf == Snone){
		if(n <= Vintmax)
			base = Vint;
		else if(n <= Vuintmax)
			base = Vuint;
		else if(n <= Vlongmax)
			base = Vlong;
		else if(n <= Vulongmax)
			base = Vulong;
		else if(n <= Vvlongmax)
			base = Vvlong;
		else
			base = Vuvlong;
	}else if(suf == Snone){
		if(n <= Vintmax)
			base = Vint;
		else if(n <= Vlongmax)
			base = Vlong;
		else if(n <= Vulongmax)
			base = Vulong;
		else if(n <= Vvlongmax)
			base = Vvlong;
		else
			base = Vuvlong;
	}else if(suf == Su){
		if(n <= Vuintmax)
			base = Vuint;
		else if(n <= Vulongmax)
			base = Vulong;
		else
			base = Vuvlong;
	}else if(suf == Sul){
		if(n <= Vulongmax)
			base = Vulong;
		else
			base = Vuvlong;
	}else if(suf == Sull)
		base = Vuvlong;
	else if(suf == Sl){
		if(n <= Vlongmax)
			base = Vlong;
		else if(n <= Vulongmax)
			base = Vulong;
		else if(n <= Vvlongmax)
			base = Vvlong;
		else
			base = Vuvlong;
	}else if(suf == Sll){
		if(n <= Vvlongmax)
			base = Vvlong;
		else
			base = Vuvlong;
	}else if(suf == Sk){
		base = Vuvlong;
		n <<= 10;
	}else if(suf == Sm){
		base = Vuvlong;
		n <<= 20;
	}else if(suf == Sg){
		base = Vuvlong;
		n <<= 30;
	}else if(suf == St){
		base = Vuvlong;
		n <<= 40;
	}else
		fatal("bug");

	lit->base = base;
	lit->v.u = n;
	return 0;
}

Expr*
doconst(U *ctx, char *s, unsigned long len)
{
	Lit lit;
	Expr *e;
	char *err;
	lit.base = 0;
	if(0 != parselit(s, len, &lit, 0, &err)) {
		parseerror(ctx, err);
		return 0;
	}
	e = Zval(mkvallitcvalenc(lit.base, lit.v));
	e->src = mksrc(&ctx->inp->src);
	return e;
}

Expr*
dosym(char *s, unsigned long len)
{
	return Zval(mkvalcid(mkcid(s+1, len-1)));
}

static char* doexpandstr(char *s, unsigned long len, int wide,
			 unsigned long* nlen)
{
	int c;
	const char *r, *z;
	char *w, *ret;
	unsigned noct;

	r = s;
	z = s+len;

	if (!wide) {
		ret = w = s;
	} else {
		ret = w = malloc((len + 1) * (wide ? 2 : 1));
	}

#define WRITEB(src, dst)		\
	do {				\
		*dst++ = *src++;	\
		if (wide) {		\
			*dst++ = '\0';	\
		}			\
	} while (0)

#define WRITEB_CONST(val, dst)		\
	do {				\
		*dst++ = val;		\
		if (wide) {		\
			*dst++ = '\0';	\
		}			\
	} while (0)

	r++;			/* skip opening quote */
	while(1){
		if(r[0] == '\"'){
			/* closing quote -- check for concontenation */
			while(++r < z){
				if(r[0] == '\"'){
					r++;
					break;
				}
			}
			if(r >= z)
				break;
		}

		if(r[0] != '\\'){
			WRITEB(r, w);
			continue;
		}

		/* escape sequence */
		r++;
		switch(*r){
 		case 'n':
			c = '\n';
			r++;
			break;
		case 't':
			c = '\t';
			r++;
			break;
		case 'v':
			c = '\v';
			r++;
			break;
		case 'b':
			c = '\b';
			r++;
			break;
		case 'r':
			c = '\r';
			r++;
			break;
		case 'f':
			c = '\f';
			r++;
			break;
		case 'a':
			c = '\a';
			r++;
			break;
		case '\\':
			c = '\\';
			r++;
			break;
		case '\?':
			c = '\?';
			r++;
			break;
		case '\'':
			c = '\'';
			r++;
			break;
		case '"':
			c = '\"';
			r++;
			break;
		default:
			c = 0;
			if(*r == 'x'){
				r++;
				while(xisxdigit(*r)){
					c *= 16;
					if(xisdigit(*r))
						c += *r - '0';
					else if('a' <= *r && *r <= 'f')
						c += *r - 'a' + 10;
					else
						c += *r - 'A' + 10;
					r++;
				}
			}else{
				noct = 0;
				while(noct < 3 && xisodigit(*r)){
					c *= 8;
					c += *r - '0';
					r++;
					noct++;
				}
			}
			break;
		}
		WRITEB_CONST(c, w);
	}

	*nlen = w-ret;
	WRITEB_CONST('\0', w);
	return ret;

#undef WRITEB
#undef WRITEB_CONST
}

void
expandstr(char *s, unsigned long len, unsigned long* nlen)
{
	(void) doexpandstr(s, len, /*wide=*/0, nlen);
}

Expr*
dostr(char *s, unsigned long len)
{
	int wide;
	char *expanded;
	unsigned long nlen;
	Expr* ret;

	if (*s == 'L') {
		wide = 1;
		++s;
	} else {
		wide = 0;
	}
	expanded = doexpandstr(s, len, wide, &nlen);
	ret = Zstrn(expanded, nlen);
	if (wide) {
		free(expanded);
	}
	return ret;
}

Expr*
dotickesrc(Ysrc *src, Expr *dom, Expr *id)
{
	Expr *e;
	e = newexprsrc(src, Eticke, dom, id, 0, 0);
	return e;
}

Expr*
doticktsrc(Ysrc *src, Expr *dom, Expr *id)
{
	Expr *e;
	e = newexprsrc(src, Etickt, dom, id, 0, 0);
	return e;
}

void
dotop(U *ctx, Expr *e)
{
	ctx->el = newexprsrc(&ctx->inp->src, Eelist, e, ctx->el, 0, 0);
}

char*
internfilename(char *s, unsigned len)
{
	char *keyed;
	keyed = hgets(filenames, s, len);
	if(!keyed){
		keyed = emalloc(len+1);
		memcpy(keyed, s, len);
		hputs(filenames, keyed, len, keyed);
	}
	return keyed;
}

static void
pushyy(U *ctx, char *filename, u32 flen, unsigned line, char *buf, u64 blen,
       int dofree)
{
	char *keyed;

	if(ctx->inp == 0)
		ctx->inp = ctx->in;
	else
		ctx->inp++;
	if(ctx->inp >= ctx->in+MaxIn)
		fatal("maximum include depth exceeded");
	keyed = 0;
	if(filename)
		keyed = internfilename(filename, flen);
	ctx->inp->src.filename = keyed;
	ctx->inp->yy = mkyystatestr(buf, blen);
	ctx->inp->src.line = line;
	ctx->inp->src.col = 0;
	ctx->inp->dofree = dofree;
	ctx->inp->buf = buf;
	setyystate(ctx->inp->yy);
}

int
popyy(U *ctx)
{
	if(ctx->inp == 0)
		return 0;
	ctx->inp->src.filename = 0;
	freeyystate(ctx->inp->yy);
	if(ctx->inp->dofree)
		efree(ctx->inp->buf);
	if(ctx->inp == ctx->in){
		ctx->inp = 0;
		return 0;
	}
	ctx->inp--;
	setyystate(ctx->inp->yy);
	return 1;
}

int
maybepopyy(U *ctx)
{
	/* keep top context in case parser needs to reduce */
	if(ctx->inp == ctx->in)
		return 0;
	return popyy(ctx);
}

int
tryinclude(U *ctx, char *raw)
{
	char *p, *q, *path, *buf, *full, **lp;
	unsigned len;
	int f;

	f = '"';
	p = strchr(raw, '"');
	if(!p){
		p = strchr(raw, '<');
		f = '>';
	}
	if(!p)
		fatal("bug");

	p++;
	q = strchr(p, f);
	if(!q)
		fatal("bug");
	*q = 0;

	buf = 0;
	full = 0;
	if(f == '>' && p[0] != '/' && p[0] != '.'){
		/* use load path */
		lp = cqctloadpath;
		while(*lp){
			len = strlen(*lp)+1+strlen(p)+1;
			full = emalloc(len);
			snprint(full, len, "%s/%s", *lp, p);
			buf = readfile(full);
			if(buf)
				break;
			efree(full);
			full = 0;
			lp++;
		}
	}else{
		if(p[0] != '/' && ctx->inp->src.filename){
			path = xstrdup(ctx->inp->src.filename);
			len = strlen(path)+1+strlen(p)+1;
			full = emalloc(len);
			snprint(full, len, "%s/%s", dirname(path), p);
			efree(path);
		}else
			full = xstrdup(p);
		buf = readfile(full);
	}
	if(buf == 0) {
		parseerror(ctx, "cannot @include %s: %s", p, strerror(errno));
	} else {
		pushyy(ctx, full, strlen(full), 1, buf, strlen(buf), 1);
	}
	efree(full);
	return buf != 0;
}

Expr*
doparse(U *ctx, char *buf, u64 len, char *whence, u32 wlen, unsigned line)
{
	int yy;
	Expr *rv;

	pushyy(ctx, whence, wlen, line, buf, len, 0);
	ctx->el = nullelistsrc(&ctx->inp->src);
	yy = yyparse(ctx);
	if(yy == 1) {
		char buf[256];
		buf[0] = '\0';
		if (ctx->parse_error) {
			strncpy(buf, ctx->parse_error, sizeof(buf) - 1);
			efree(ctx->parse_error);
		}
		while (popyy(ctx)) { }
		yylex_destroy();
		if (ctx->vm) {
			vmerr(ctx->vm, "%s", buf);
		} else {
			cprintf(&l1stderr, "%s\n", buf);
			longjmp(ctx->jmp, 1);
		}
		fatal("unreachable return from parse error");
	}
	if(yy != 0)
		fatal("parser failure");
	rv = invert(ctx->el);
	ctx->el = 0;
	popyy(ctx);
	/* FIXME: does bison normally call yylex_destroy implicitly?
	   http://www.mail-archive.com/bison-patches@gnu.org/msg01521.html
	*/
	yylex_destroy();
	return rv;
}

void
initparse(void)
{
	filenames = mkhts();
}

static void
freefilename(void *u, char *k, void *v)
{
	USED(u);
	USED(v);
	efree(k);
}

void
finiparse(void)
{
	hforeach(filenames, freefilename, 0);
	freeht(filenames);
}
