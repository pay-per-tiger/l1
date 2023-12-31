%{
#include "sys.h"
#include "util.h"
#include "syscqct.h"

extern int yylex();
extern char *yytext;

%}

%union{
	Expr *expr;
	struct {
		/* GLR may pick tokens from input stream more than
		   once; remembering length in char-based tokens
		   ensures that we get the same token each time,
		   regardless of state of yytext. */
		char *p;
		unsigned long len;
	} chars;
	int kind;
}

%token <chars> IDENTIFIER SYMBOL CONSTANT STRING_LITERAL CONST VOLATILE DATA
%token <chars> ATIDENTIFIER SYNTAXID
%token SIZEOF TYPENAME TYPEOF TYPEDEF DEFINE DEFLOC DEFREC DEFSTX CONTAINEROF
%token PTR_OP INC_OP DEC_OP LEFT_OP RIGHT_OP LE_OP GE_OP EQ_OP NE_OP
%token AND_OP OR_OP MUL_ASSIGN DIV_ASSIGN MOD_ASSIGN ADD_ASSIGN
%token SUB_ASSIGN LEFT_ASSIGN RIGHT_ASSIGN AND_ASSIGN XOR_ASSIGN OR_ASSIGN
%token CAST_ASSIGN XCAST_ASSIGN GOTO
%token GLOBAL LOCAL LAMBDA NAMES LET LAPPLY
%token BOOL CHAR SHORT INT LONG SIGNED UNSIGNED FLOAT DOUBLE VOID
%token STRUCT UNION ENUM ELLIPSIS
%token IF ELSE SWITCH WHILE DO FOR CONTINUE BREAK RETURN CASE DEFAULT
%token SYNTAXQUOTE SYNTAXQUASI SYNTAXUNQUOTE SYNTAXSPLICE SYNTAXLIST
%token LPAIR RPAIR NOBIND_PRE MATCH
%token ATFILE ATLINE
%token PARSEERROR

%type <expr> base base_list
%type <expr> declaration typedef specifier_list constant_expression
%type <expr> declarator_list primary_expression postfix_expression
%type <expr> argument_expression_list unary_expression cast_expression
%type <expr> argument_expression_list_element
%type <expr> multiplicative_expression additive_expression shift_expression
%type <expr> relational_expression equality_expression and_expression
%type <expr> exclusive_or_expression inclusive_or_expression maybe_expression
%type <expr> logical_and_expression logical_or_expression conditional_expression
%type <expr> assignment_expression lambda_expression expression root_expression
%type <expr> names_expression names_declaration_list names_declaration
%type <expr> lapply_expression
%type <expr> arg_id_list id_list id_list_element local_list local type_specifier
%type <expr> _id id maybeid struct_or_union_specifier
%type <expr> struct_declaration_list struct_declaration struct_size
%type <expr> struct_declarator_list struct_declarator enum_specifier
%type <expr> enumerator_list enumerator declarator direct_declarator pointer
%type <expr> abstract_declarator direct_abstract_declarator
%type <expr> parameter_type_list parameter_list parameter_declaration
%type <expr> statement
%type <expr> statement_list_element
%type <expr> compound_statement statement_list
%type <expr> expression_statement define_statement labeled_statement
%type <expr> selection_statement iteration_statement jump_statement
%type <expr> global_statement let_expression
%type <expr> type_name tn_type_specifier_tick tn_type_qual_specifier
%type <expr> tn_parameter_type_list tn_parameter_list
%type <expr> tn_parameter_declaration tn_abstract_declarator
%type <expr> tn_direct_abstract_declarator tn_declarator tn_direct_declarator
%type <expr> tn_param_type_specifier tn_param_struct_or_union_specifier
%type <expr> tn_param_type_qual_specifier
%type <expr> tn_param_enum_specifier
%type <expr> table_init table_init_list
%type <expr> maybe_attr
%type <expr> syntax_list
%type <expr> defstx_statement
%type <expr> syntax_expression
%type <expr> mcall_expression
%type <expr> src_expression
%type <expr> quote_expression
%type <expr> mcall_statement
%type <expr> atid syntaxid
%type <expr> unquote_statement unquote_expr
%type <expr> splice_expr
%type <expr> pattern pattern_list var_pat_list rec_pat_list
%type <expr> table_init_pattern table_init_pattern_list

%type <kind> unary_operator assignment_operator struct_or_union struct_or_union_or_enum define

%start translation_unit_seq
%debug
%glr-parser
%pure-parser
%parse-param {U *ctx}
%lex-param   {U *ctx}
%expect 1
%expect-rr 15
%{
	static void yyerror(U *ctx, const char *s);
	static Expr* castmerge(YYSTYPE e1, YYSTYPE e2);
	static Expr* ofmerge(YYSTYPE e1, YYSTYPE e2);
%}
%%


_id
	: IDENTIFIER
	{ $$ = doidnsrc(&ctx->inp->src, $1.p, $1.len); }
	;

unquote_expr
	: SYNTAXUNQUOTE _id
	{ $$ = newexprsrc(&ctx->inp->src, Estxunquote, $2, 0, 0, 0); }
	| SYNTAXUNQUOTE '(' expression ')'
	{ $$ = newexprsrc(&ctx->inp->src, Estxunquote, $3, 0, 0, 0); }
	;

splice_expr
	: SYNTAXSPLICE _id
	{ $$ = newexprsrc(&ctx->inp->src, Estxsplice, $2, 0, 0, 0); }
	| SYNTAXSPLICE '(' expression ')'
	{ $$ = newexprsrc(&ctx->inp->src, Estxsplice, $3, 0, 0, 0); }
	;

id
	: _id
	| unquote_expr
	;

atid
	: ATIDENTIFIER
	{ $$ = doidnsrc(&ctx->inp->src, $1.p+1, $1.len-1); }
	;

syntaxid
	: SYNTAXID
	{ $$ = doidnsrc(&ctx->inp->src, $1.p+1, $1.len-1); }
	;

maybeid
	: id
	|
	{ $$ = 0; }
	;

lambda
	: LAMBDA
	;

lambda_expression
	: lambda '(' arg_id_list ')' compound_statement
	{ $$ = newexprsrc(&ctx->inp->src, Elambda, invert($3), $5, 0, 0); }
	| lambda '(' ')' compound_statement
	{ $$ = newexprsrc(&ctx->inp->src, Elambda, nullelist(), $4, 0, 0); }
	;

let_expression
	: LET compound_statement
	{ $$ = $2; }
	;

quote_expression
	: SYNTAXQUOTE statement_list '}'
	{ $$ = newexprsrc(&ctx->inp->src, Estxquote, invert($2), 0, 0, 0); }
	| SYNTAXQUOTE expression '}'
	{ $$ = newexprsrc(&ctx->inp->src, Estxquote, $2, 0, 0, 0); }
	| SYNTAXQUASI statement_list '}'
	{ $$ = newexprsrc(&ctx->inp->src, Estxquasi, invert($2), 0, 0, 0); }
	| SYNTAXQUASI expression '}'
	{ $$ = newexprsrc(&ctx->inp->src, Estxquasi, $2, 0, 0, 0); }
	;

syntax_expression
	: syntaxid '(' argument_expression_list ')'
	{ $$ = newexprsrc(&ctx->inp->src, Estx, $1, invert($3), 0, 0); }
	| syntaxid '(' ')'
	{ $$ = newexprsrc(&ctx->inp->src, Estx, $1, nullelist(), 0, 0); }
	| syntaxid
	{ $$ = newexprsrc(&ctx->inp->src, Estx, $1, nullelist(), 0, 0); }
	;

mcall_expression
	: atid '(' ')'
	{ $$ = newexprsrc(&ctx->inp->src, Emcall, $1, nullelist(), 0, 0); }
	| atid '(' argument_expression_list ')'
        { $$ = newexprsrc(&ctx->inp->src, Emcall, $1, invert($3), 0, 0); }
	;

src_expression
	: ATLINE CONSTANT
	{
		Lit lit;
		char *err;
		if(0 != parselit($2.p, $2.len, &lit, 0, &err)) {
			parseerror(ctx, err);
			YYERROR;
		}
		/* FIXME: check type of literal */
		ctx->inp->src.line = (unsigned)lit.v.u;
		$$ = newexprsrc(&ctx->inp->src, Enil, 0, 0, 0, 0);
	}
	| ATLINE
	{
		$$ = Zuint(ctx->inp->src.line);
	}
	| ATFILE STRING_LITERAL
	{
		unsigned long nlen;
		expandstr($2.p, $2.len, &nlen);
		ctx->inp->src.filename = internfilename($2.p, nlen);
		$$ = newexprsrc(&ctx->inp->src, Enil, 0, 0, 0, 0);
	}
	| ATFILE
	{
		$$ = Zstr(ctx->inp->src.filename);
	}
	;

table_init
	: root_expression ':' root_expression
	{ $$ = newexprsrc(&ctx->inp->src, Eelist,
			  $1,
			  newexprsrc(&ctx->inp->src, Eelist,
				     $3, nullelist(), 0, 0),
			  0, 0);
	}
	;

table_init_list
	: table_init
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $1, nullelist(), 0, 0); }
	| table_init_list ',' table_init
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $3, $1, 0, 0); }
	;

syntax_list
	: SYNTAXLIST ']'
	{ $$ = newexprsrc(&ctx->inp->src, Estxlist, nullelist(), 0, 0, 0); }
	| SYNTAXLIST argument_expression_list ']'
	{ $$ = newexprsrc(&ctx->inp->src, Estxlist, invert($2), 0, 0, 0); }
	| SYNTAXLIST argument_expression_list ',' ']'
	{ $$ = newexprsrc(&ctx->inp->src, Estxlist, invert($2), 0, 0, 0); }
	;

primary_expression
	: id
	| id '`' id
	{ $$ = dotickesrc(&ctx->inp->src, $1, $3); }
	| SYMBOL
	{ $$ = dosym($1.p, $1.len); }
	| CONSTANT
	{ $$ = doconst(ctx, $1.p, $1.len); if (!$$) { YYERROR; } }
	| STRING_LITERAL
	{ $$ = dostr($1.p, $1.len); }
	| DATA
	{ $$ = Zstrn($1.p, $1.len); efree($1.p); }
	| '(' expression ')'
	{ $$ = $2; }
        | LPAIR root_expression ',' root_expression RPAIR
	{ $$ = newexprsrc(&ctx->inp->src, Epair, $2, $4, 0, 0); }
	| '[' ']'
	{ $$ = newexprsrc(&ctx->inp->src, Elist, nullelist(), 0, 0, 0); }
	| '[' argument_expression_list ']'
	{ $$ = newexprsrc(&ctx->inp->src, Elist, invert($2), 0, 0, 0); }
	| '[' argument_expression_list ',' ']'
	{ $$ = newexprsrc(&ctx->inp->src, Elist, invert($2), 0, 0, 0); }
	| '[' argument_expression_list ELLIPSIS ']'
	{ Expr *ell = newexprsrc(&ctx->inp->src, Eellipsis, 0, 0, 0, 0);
          $$ = newexprsrc(&ctx->inp->src, Elist,
                          invert(newexprsrc(&ctx->inp->src, Eelist,
                                            ell, $2, 0, 0)), 0, 0, 0); }
	| '[' ':' ']'
	{ $$ = newexprsrc(&ctx->inp->src, Etab, nullelist(), 0, 0, 0); }
	| '[' table_init_list ']'
	{ $$ = newexprsrc(&ctx->inp->src, Etab, invert($2), 0, 0, 0); }
	| '[' table_init_list ',' ']'
	{ $$ = newexprsrc(&ctx->inp->src, Etab, invert($2), 0, 0, 0); }
	| syntax_list
	| lambda_expression
	| let_expression
	| quote_expression
	| mcall_expression
	| src_expression
	;

pattern
	: id
	| CONSTANT
	{ $$ = doconst(ctx, $1.p, $1.len); }
	| SYMBOL
	{ $$ = dosym($1.p, $1.len); }
	| STRING_LITERAL
	{ $$ = dostr($1.p, $1.len); }
	| '(' pattern ')'
	{ $$ = $2; }
        | LPAIR pattern ',' pattern RPAIR
	{ $$ = newexprsrc(&ctx->inp->src, Epair, $2, $4, 0, 0); }
	| '[' ']'
	{ $$ = newexprsrc(&ctx->inp->src, Elist, nullelist(), 0, 0, 0); }
	| '[' pattern_list ']'
	{ $$ = newexprsrc(&ctx->inp->src, Elist, invert($2), 0, 0, 0); }
	| '[' pattern_list ',' ']'
	{ $$ = newexprsrc(&ctx->inp->src, Elist, invert($2), 0, 0, 0); }
	| '[' pattern_list ELLIPSIS ']'
	{ Expr *ell = newexprsrc(&ctx->inp->src, Eellipsis, 0, 0, 0, 0);
          $$ = newexprsrc(&ctx->inp->src, Elist,
                          invert(newexprsrc(&ctx->inp->src, Eelist,
                                            ell, $2, 0, 0)), 0, 0, 0); }
	| '[' ':' ']'
	{ $$ = newexprsrc(&ctx->inp->src, Etab, nullelist(), 0, 0, 0); }
	| '[' table_init_pattern_list ']'
	{ $$ = newexprsrc(&ctx->inp->src, Etab, invert($2), 0, 0, 0); }
	| '[' table_init_pattern_list ',' ']'
	{ $$ = newexprsrc(&ctx->inp->src, Etab, invert($2), 0, 0, 0); }
	| id '(' rec_pat_list ')'
	{ $$ = newexprsrc(&ctx->inp->src, Ecall, $1, invert($3), 0, 0); }
	| id '(' ')'
	{ $$ = newexprsrc(&ctx->inp->src, Ecall, $1, nullelist(), 0, 0); }
	| syntaxid '(' pattern_list ')'
	{ $$ = newexprsrc(&ctx->inp->src, Estx, $1, invert($3), 0, 0); }
	| syntaxid '(' ')'
	{ $$ = newexprsrc(&ctx->inp->src, Estx, $1, nullelist(), 0, 0); }
	| syntaxid
	{ $$ = newexprsrc(&ctx->inp->src, Estx, $1, nullelist(), 0, 0); }
	| syntax_list
	;

rec_pat_list
	: pattern_list
	| var_pat_list
	;

pattern_list
	: pattern
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $1, nullelist(), 0, 0); }
	| pattern_list ',' pattern
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $3, $1, 0, 0); }
	;

var_pat_list
	: id '=' pattern
	{ $$ = newexprsrc(&ctx->inp->src, Eelist,
                          newbinopsrc(&ctx->inp->src, Eeq, $1, $3),
                          nullelist(),
                          0, 0); }
	| var_pat_list ',' id '=' pattern
	{ $$ = newexprsrc(&ctx->inp->src, Eelist,
                          newbinopsrc(&ctx->inp->src, Eeq, $3, $5),
                          $1,
                          0, 0); }
	;

table_init_pattern_list
	: table_init_pattern
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $1, nullelist(), 0, 0); }
	| table_init_pattern_list ',' table_init_pattern
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $3, $1, 0, 0); }
	;

table_init_pattern
	: pattern ':' pattern
	{ /* key may not actually bind variables, but this will get
             caught during compilation. */
          $$ = newexprsrc(&ctx->inp->src, Eelist,
			  $1,
			  newexprsrc(&ctx->inp->src, Eelist,
				     $3, nullelist(), 0, 0),
			  0, 0);
	}
	;

postfix_expression
	: primary_expression
	| postfix_expression '[' expression ']'
	{ $$ = newexprsrc(&ctx->inp->src, Earef, $1, $3, 0, 0); }
	| postfix_expression '(' ')'
	{ $$ = newexprsrc(&ctx->inp->src, Ecall, $1, nullelist(), 0, 0); }
	| postfix_expression '(' argument_expression_list ')'
	{ $$ = newexprsrc(&ctx->inp->src, Ecall, $1, invert($3), 0, 0); }
	| postfix_expression '.' id
	{ $$ = newexprsrc(&ctx->inp->src, Edot, $1, $3, 0, 0); }
	| postfix_expression PTR_OP id
	{ $$ = newexprsrc(&ctx->inp->src, Earrow, $1, $3, 0, 0); }
	| postfix_expression INC_OP
	{ $$ = newexprsrc(&ctx->inp->src, Epostinc, $1, 0, 0, 0); }
	| postfix_expression DEC_OP
	{ $$ = newexprsrc(&ctx->inp->src, Epostdec, $1, 0, 0, 0); }
	| CONTAINEROF '(' expression ',' type_name ',' id ')'
        { $$ = newexprsrc(&ctx->inp->src, Econtainer, $3, $5, $7, 0); }
	;

argument_expression_list_element
	: root_expression
	| splice_expr
	;

argument_expression_list
	: argument_expression_list_element
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $1, nullelist(), 0, 0); }
	| argument_expression_list ',' argument_expression_list_element
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $3, $1, 0, 0); }
	;

unary_expression
	: postfix_expression
	| syntax_expression
	| INC_OP unary_expression
	{ $$ = newexprsrc(&ctx->inp->src, Epreinc, $2, 0, 0, 0); }
	| DEC_OP unary_expression
	{ $$ = newexprsrc(&ctx->inp->src, Epredec, $2, 0, 0, 0); }
	| unary_operator cast_expression
	{ $$ = newexprsrc(&ctx->inp->src, $1, $2, 0, 0, 0); }
	| SIZEOF unary_expression			%merge <ofmerge>
	{ $$ = newexprsrc(&ctx->inp->src, Esizeofe, $2, 0, 0, 0); }
	| SIZEOF '(' type_name ')'			%merge <ofmerge>
	{ $$ = newexprsrc(&ctx->inp->src, Esizeoft, $3, 0, 0, 0); }
	| TYPEOF unary_expression			%merge <ofmerge>
	{ $$ = newexprsrc(&ctx->inp->src, Etypeofe, $2, 0, 0, 0); }
	| TYPEOF '(' type_name ')'			%merge <ofmerge>
	{ $$ = newexprsrc(&ctx->inp->src, Etypeoft, $3, 0, 0, 0); }
	| TYPENAME '(' type_name ')'
	{ $$ = newexprsrc(&ctx->inp->src, Emkctype, $3, 0, 0, 0); }
	;

unary_operator
	: '&'
	{ $$ = Eref; }
	| '*'
	{ $$ = Ederef; }
	| '+'
	{ $$ = Euplus; }
	| '-'
	{ $$ = Euminus; }
	| '~'
	{ $$ = Eutwiddle; }
	| '!'
	{ $$ = Eunot; }
	;

cast_expression
	: unary_expression				%merge <castmerge>
	| '(' type_name ')' cast_expression		%merge <castmerge>
	{ $$ = newexprsrc(&ctx->inp->src, Ecast, $2, $4, 0, 0); }
	| '{' expression '}' cast_expression
	{ $$ = newbinopsrc(&ctx->inp->src, Excast, $2, $4); }
	;

multiplicative_expression
	: cast_expression				%merge <castmerge>
	| multiplicative_expression '*' cast_expression	%merge <castmerge>
	{ $$ = newbinopsrc(&ctx->inp->src, Emul, $1, $3); }
	| multiplicative_expression '/' cast_expression
	{ $$ = newbinopsrc(&ctx->inp->src, Ediv, $1, $3); }
	| multiplicative_expression '%' cast_expression
	{ $$ = newbinopsrc(&ctx->inp->src, Emod, $1, $3); }
	;

additive_expression
	: multiplicative_expression                          %merge <castmerge>
	| additive_expression '+' multiplicative_expression  %merge <castmerge>
	{ $$ = newbinopsrc(&ctx->inp->src, Eadd, $1, $3); }
	| additive_expression '-' multiplicative_expression  %merge <castmerge>
	{ $$ = newbinopsrc(&ctx->inp->src, Esub, $1, $3); }
	;

shift_expression
	: additive_expression
	| shift_expression LEFT_OP additive_expression
	{ $$ = newbinopsrc(&ctx->inp->src, Eshl, $1, $3); }
	| shift_expression RIGHT_OP additive_expression
	{ $$ = newbinopsrc(&ctx->inp->src, Eshr, $1, $3); }
	;

relational_expression
	: shift_expression
	| relational_expression '<' shift_expression
	{ $$ = newbinopsrc(&ctx->inp->src, Elt, $1, $3); }
	| relational_expression '>' shift_expression
	{ $$ = newbinopsrc(&ctx->inp->src, Egt, $1, $3); }
	| relational_expression LE_OP shift_expression
	{ $$ = newbinopsrc(&ctx->inp->src, Ele, $1, $3); }
	| relational_expression GE_OP shift_expression
	{ $$ = newbinopsrc(&ctx->inp->src, Ege, $1, $3); }
	;

equality_expression
	: relational_expression
	| equality_expression EQ_OP relational_expression
	{ $$ = newbinopsrc(&ctx->inp->src, Eeq, $1, $3); }
	| equality_expression NE_OP relational_expression
	{ $$ = newbinopsrc(&ctx->inp->src, Eneq, $1, $3); }
	;

and_expression
	: equality_expression                       %merge <castmerge>
	| and_expression '&' equality_expression    %merge <castmerge>
	{ $$ = newbinopsrc(&ctx->inp->src, Eband, $1, $3); }
	;

exclusive_or_expression
	: and_expression
	| exclusive_or_expression '^' and_expression
	{ $$ = newbinopsrc(&ctx->inp->src, Ebxor, $1, $3); }
	;

inclusive_or_expression
	: exclusive_or_expression
	| inclusive_or_expression '|' exclusive_or_expression
	{ $$ = newbinopsrc(&ctx->inp->src, Ebor, $1, $3); }
	;

logical_and_expression
	: inclusive_or_expression
	| logical_and_expression AND_OP inclusive_or_expression
	{ $$ = newexprsrc(&ctx->inp->src, Eland, $1, $3, 0, 0); }
	;

logical_or_expression
	: logical_and_expression
	| logical_or_expression OR_OP logical_and_expression
	{ $$ = newexprsrc(&ctx->inp->src, Elor, $1, $3, 0, 0); }
	;

conditional_expression
	: logical_or_expression
	| logical_or_expression '?' expression ':' conditional_expression
	{ $$ = newexprsrc(&ctx->inp->src, Econd, $1, $3, $5, 0); }
	;

assignment_expression
	: conditional_expression
	| unary_expression assignment_operator root_expression
	{ if($2 == Eg)
	  	$$ = newexprsrc(&ctx->inp->src, $2, $1, $3, 0, 0);
	  else
	  	$$ = newgopsrc(&ctx->inp->src, $2, $1, $3);
	}
	;

assignment_operator
	: '='
	{ $$ = Eg; }
	| ADD_ASSIGN
	{ $$ = Egadd; }
	| AND_ASSIGN
	{ $$ = Egband; }
	| OR_ASSIGN
	{ $$ = Egbor; }
	| XOR_ASSIGN
	{ $$ = Egbxor; }
	| DIV_ASSIGN
	{ $$ = Egdiv; }
	| MOD_ASSIGN
	{ $$ = Egmod; }
	| MUL_ASSIGN
	{ $$ = Egmul; }
	| LEFT_ASSIGN
	{ $$ = Egshl; }
	| RIGHT_ASSIGN
	{ $$ = Egshr; }
	| SUB_ASSIGN
	{ $$ = Egsub; }
	;


id_list_element
	: id
	| splice_expr
	;

id_list
	: id_list_element
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $1, nullelist(), 0, 0); }
	| id_list ',' id_list_element
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $3, $1, 0, 0); }
	;

arg_id_list
	: id_list
	{ $$ = $1; }
	| id_list ELLIPSIS
	{ $$ = newexprsrc(&ctx->inp->src, Eelist,
			  newexprsrc(&ctx->inp->src, Eellipsis, 0, 0, 0, 0),
			  $1, 0, 0);
	}
	;

names_declaration_list
	: names_declaration
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $1, nullelist(), 0, 0); }
	| names_declaration_list names_declaration
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $2, $1, 0, 0); }
	;

names_declaration
	: declaration
	| typedef
	| splice_expr
	;

names_expression
	: assignment_expression
	| NAMES expression '{' names_declaration_list '}'
	{ $$ = newexprsrc(&ctx->inp->src, Enames, $2, invert($4), 0, 0); }
	| NAMES expression '{' '}'
	{ $$ = newexprsrc(&ctx->inp->src, Enames, $2, Znull(), 0, 0); }
	;

lapply_expression
	: LAPPLY '(' root_expression ',' argument_expression_list ')'
	{ $$ = newexprsrc(&ctx->inp->src, Elapply, $3, invert($5), 0, 0); }
	| LAPPLY '(' root_expression ')'
	{ $$ = newexprsrc(&ctx->inp->src, Elapply, $3, nullelist(), 0, 0); }
	;

root_expression
	: names_expression
	| lapply_expression
	;

expression
	: root_expression
	| expression ',' root_expression
	{ $$ = newexprsrc(&ctx->inp->src, Ecomma, $1, $3, 0, 0); }
	;

constant_expression
	: conditional_expression
	;

typedef
	: TYPEDEF specifier_list declarator_list ';'
	{ $$ = newexprsrc(&ctx->inp->src, Etypedef, $2, invert($3), 0, 0); }
	;

maybe_attr
	: '@' constant_expression
	{ $$ = $2; }
	|
        { $$ = 0; }
	;

declaration
	: specifier_list ';'
	{ $$ = newexprsrc(&ctx->inp->src, Edecls, $1, Znull(), 0, 0); }
	| '@' constant_expression specifier_list declarator_list ';'
	{ $$ = newexprsrc(&ctx->inp->src, Edecls, $3, invert($4), $2, 0); }
	| specifier_list declarator_list ';'
	{ $$ = newexprsrc(&ctx->inp->src, Edecls, $1, invert($2), 0, 0); }
	;

declarator_list
	: declarator
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $1, Znull(), 0, 0); }
	| declarator_list ',' declarator
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $3, $1, 0, 0); }
	;

base
	: VOID
	{ $$ = newexprsrc(&ctx->inp->src, Evoid, 0, 0, 0, 0); }
	| BOOL
	{ $$ = newexprsrc(&ctx->inp->src, Ebool, 0, 0, 0, 0); }
	| CHAR
	{ $$ = newexprsrc(&ctx->inp->src, Echar, 0, 0, 0, 0); }
	| SHORT
	{ $$ = newexprsrc(&ctx->inp->src, Eshort, 0, 0, 0, 0); }
	| INT
	{ $$ = newexprsrc(&ctx->inp->src, Eint, 0, 0, 0, 0); }
	| LONG
	{ $$ = newexprsrc(&ctx->inp->src, Elong, 0, 0, 0, 0); }
	| FLOAT
	{ $$ = newexprsrc(&ctx->inp->src, Efloat, 0, 0, 0, 0); }
	| DOUBLE
	{ $$ = newexprsrc(&ctx->inp->src, Edouble, 0, 0, 0, 0); }
	| SIGNED
	{ $$ = newexprsrc(&ctx->inp->src, Esigned, 0, 0, 0, 0); }
	| UNSIGNED
	{ $$ = newexprsrc(&ctx->inp->src, Eunsigned, 0, 0, 0, 0); }

base_list
	: base
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $1, Znull(), 0, 0); }
	| base_list base
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $2, $1, 0, 0); }
	;

type_specifier
	: base_list
	{ $$ = newexprsrc(&ctx->inp->src, Ebase, $1, 0, 0, 0); }
	| id
	{ $$ = newexprsrc(&ctx->inp->src, Etypedef, $1, 0, 0, 0); }
	| struct_or_union_specifier
	| enum_specifier
	;

struct_or_union_specifier
	: struct_or_union maybeid '{' struct_declaration_list struct_size '}'
	{ $$ = newexprsrc(&ctx->inp->src, $1, $2, invert($4), $5, 0); }
	| struct_or_union maybeid '{' struct_declaration_list '}'
	{ $$ = newexprsrc(&ctx->inp->src, $1, $2, invert($4), 0, 0); }
	| struct_or_union maybeid '{' struct_size '}'
	{ $$ = newexprsrc(&ctx->inp->src, $1, $2, Znull(), $4, 0); }
	| struct_or_union maybeid '{'  '}'
	{ $$ = newexprsrc(&ctx->inp->src, $1, $2, Znull(), 0, 0); }
	| struct_or_union id
	{ $$ = newexprsrc(&ctx->inp->src, $1, $2, 0, 0, 0); }
	;

struct_or_union
	: STRUCT
	{ $$ = Estruct; }
	| UNION
	{ $$ = Eunion; }
	;

struct_or_union_or_enum
	: STRUCT
	{ $$ = Estruct; }
	| UNION
	{ $$ = Eunion; }
	| ENUM
	{ $$ = Eenum; }
	;

struct_declaration_list
	: struct_declaration
	{
		/* labels yield null struct_declarations */
		if($1)
			$$ = newexprsrc(&ctx->inp->src, Eelist,
					$1, Znull(), 0, 0);
		else
			$$ = Znull();
	}
	| struct_declaration_list struct_declaration
	{
		/* labels yield null struct_declarations */
	 	if($2)
			$$ = newexprsrc(&ctx->inp->src, Eelist, $2, $1, 0, 0);
		else
			$$ = $1; 
	}
	;

struct_declaration
	: '@' constant_expression specifier_list struct_declarator_list ';'
	{ $$ = newexprsrc(&ctx->inp->src, Efields, $3, invert($4), $2, 0); }
	| '@' constant_expression specifier_list ';'
	{ $$ = newexprsrc(&ctx->inp->src, Efields, $3, Znull(), $2, 0); }
	| specifier_list ';'
	{ $$ = newexprsrc(&ctx->inp->src, Efields, $1, Znull(), 0, 0); }
	| specifier_list struct_declarator_list ';'
	{ $$ = newexprsrc(&ctx->inp->src, Efields, $1, invert($2), 0, 0); }
	| '@' '@' constant_expression specifier_list struct_declarator ':' constant_expression ';'
	{ $$ = newexprsrc(&ctx->inp->src, Ebitfield, $4, $5, $3, $7); }
	| specifier_list struct_declarator ':' constant_expression ';'
	{ $$ = newexprsrc(&ctx->inp->src, Ebitfield, $1, $2, 0, $4); }
	/* accept (but discard) c++ labels such as "public:" */
	| id ':'
	{ $$ = 0; }
	;

struct_size
	: '@' constant_expression ';'
	{ $$ = $2; }
	;

// discard type qualifiers
type_qualifier
	: CONST
	| VOLATILE
	;

type_qualifier_list
	: type_qualifier
	| type_qualifier type_qualifier_list
	;

maybe_type_qualifier
	: type_qualifier_list
	|
	;

specifier_list
	: type_specifier
	| type_qualifier_list type_specifier
	{ $$ = $2; }
	| type_specifier type_qualifier_list
	{ $$ = $1; }
	;

struct_declarator_list
	: struct_declarator
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $1, Znull(), 0, 0); }
	| struct_declarator_list ',' struct_declarator
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $3, $1, 0, 0); }
	;

struct_declarator
	: declarator
	;

enum_specifier
	: ENUM maybeid '{' enumerator_list '}'
	{ $$ = newexprsrc(&ctx->inp->src, Eenum, $2, invert($4), 0, 0); }
	| ENUM maybeid '{' enumerator_list ',' '}'
	{ $$ = newexprsrc(&ctx->inp->src, Eenum, $2, invert($4), 0, 0); }
	| ENUM maybeid '{' '}'
	{ $$ = newexprsrc(&ctx->inp->src, Eenum, $2, Znull(), 0, 0); }
	| ENUM maybeid '{' ',' '}'
	{ $$ = newexprsrc(&ctx->inp->src, Eenum, $2, Znull(), 0, 0); }
	| ENUM id
	{ $$ = newexprsrc(&ctx->inp->src, Eenum, $2, 0, 0, 0); }
	;

enumerator_list
	: enumerator
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $1, Znull(), 0, 0); }
	| enumerator_list ',' enumerator
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $3, $1, 0, 0); }
	;

/* typedef names and enumator components are in the same
   overload class, so use id not tag. (FIXME: really?) */
enumerator
	: id
	{ $$ = newexprsrc(&ctx->inp->src, Eenumel, $1, 0, 0, 0); }
	| id '=' constant_expression
	{ $$ = newexprsrc(&ctx->inp->src, Eenumel, $1, $3, 0, 0); }
	;

declarator
	: pointer direct_declarator
	{ $$ = ptrto($1, $2); }
	| direct_declarator
	;

direct_declarator
	: id
	{ $$ = $1; }
	| '(' declarator ')'
	{ $$ = $2; }
	| direct_declarator '[' constant_expression ']'
	{ $$ = newexprsrc(&ctx->inp->src, Earr, $1, $3, 0, 0); }
	| direct_declarator '[' ']'
	{ $$ = newexprsrc(&ctx->inp->src, Earr, $1, 0, 0, 0); }
	| direct_declarator '(' parameter_type_list ')' maybe_type_qualifier
	{ $$ = newexprsrc(&ctx->inp->src, Efun, $1, $3, 0, 0); }
	| direct_declarator '(' ')' maybe_type_qualifier
	{ $$ = newexprsrc(&ctx->inp->src, Efun, $1, nullelist(), 0, 0); }
	;

abstract_declarator
	: pointer
	| direct_abstract_declarator
	| pointer direct_abstract_declarator
	{ $$ = ptrto($1, $2); }
	;

direct_abstract_declarator
	: '(' abstract_declarator ')'
	{ $$ = $2; }
	| '[' ']'
	{ $$ = newexprsrc(&ctx->inp->src, Earr, 0, 0, 0, 0); }
	| '[' constant_expression ']'
	{ $$ = newexprsrc(&ctx->inp->src, Earr, 0, $2, 0, 0); }
	| direct_abstract_declarator '[' ']'
	{ $$ = newexprsrc(&ctx->inp->src, Earr, $1, 0, 0, 0); }
	| direct_abstract_declarator '[' constant_expression ']'
	{ $$ = newexprsrc(&ctx->inp->src, Earr, $1, $3, 0, 0); }
	| '(' ')' maybe_type_qualifier
	{ $$ = newexprsrc(&ctx->inp->src, Efun, 0, Znull(), 0, 0); }
	| direct_abstract_declarator '(' ')' maybe_type_qualifier
	{ $$ = newexprsrc(&ctx->inp->src, Efun, $1, Znull(), 0, 0); }
	| direct_abstract_declarator '(' parameter_type_list ')' maybe_type_qualifier
	{ $$ = newexprsrc(&ctx->inp->src, Efun, $1, $3, 0, 0); }
	;

pointer
	: '*'
	{ $$ = newexprsrc(&ctx->inp->src, Eptr, 0, 0, 0, 0); }
	| '*' type_qualifier_list
	{ $$ = newexprsrc(&ctx->inp->src, Eptr, 0, 0, 0, 0); }
	| '*' pointer
	{ $$ = newexprsrc(&ctx->inp->src, Eptr, $2, 0, 0, 0); }
	| '*' type_qualifier_list pointer
	{ $$ = newexprsrc(&ctx->inp->src, Eptr, $3, 0, 0, 0); }
	;

parameter_type_list
	: parameter_list
	{ $$ = invert($1); }
	| parameter_list ',' ELLIPSIS
	{ $$ = invert($1); }
	;

parameter_list
	: parameter_declaration
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $1, Znull(), 0, 0); }
	| parameter_list ',' parameter_declaration
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $3, $1, 0, 0); }
	;

parameter_declaration
	: maybe_attr specifier_list declarator
	{ $$ = newexprsrc(&ctx->inp->src, Edecl, $2, $3, $1, 0); }
	| maybe_attr specifier_list abstract_declarator
	{ $$ = newexprsrc(&ctx->inp->src, Edecl, $2, $3, $1, 0); }
	| maybe_attr specifier_list
	{ $$ = newexprsrc(&ctx->inp->src, Edecl, $2, 0, $1, 0); }
	;

type_name
	: tn_type_qual_specifier
	{ $$ = newexprsrc(&ctx->inp->src, Etypename, $1, 0, 0, 0); }
        | tn_type_qual_specifier tn_abstract_declarator
	{ $$ = newexprsrc(&ctx->inp->src, Etypename, $1, $2, 0, 0); }
	;

tn_type_qual_specifier
	: tn_type_specifier_tick
	| type_qualifier_list tn_type_specifier_tick
	{ $$ = $2; }
	| tn_type_specifier_tick type_qualifier_list
	{ $$ = $1; }
	;

tn_type_specifier_tick
	: base_list
	{ $$ = newexprsrc(&ctx->inp->src, Ebase, $1, 0, 0, 0); }
	| id '`' base_list
	{ $$ = doticktsrc(&ctx->inp->src, $1,
			  newexprsrc(&ctx->inp->src, Ebase, $3, 0, 0, 0)); }
	| id '`' id
	{ $$ = doticktsrc(&ctx->inp->src, $1,
			  newexprsrc(&ctx->inp->src, Etypedef, $3, 0, 0, 0)); }
	| _id
	{ $$ = doticktsrc(&ctx->inp->src, 0,
			  newexprsrc(&ctx->inp->src, Etypedef, $1, 0, 0, 0)); }
	| struct_or_union_or_enum id
	{ $$ = newexprsrc(&ctx->inp->src, $1, $2, 0, 0, 0); }
	| struct_or_union_or_enum id '`' id
	{ $$ = doticktsrc(&ctx->inp->src, $2,
			  newexprsrc(&ctx->inp->src, $1, $4, 0, 0, 0)); }
	| unquote_expr
	;

tn_parameter_type_list
	: tn_parameter_list
	{ $$ = invert($1); }
	| tn_parameter_list ',' ELLIPSIS
	{ $$ = invert($1); }
	;

tn_parameter_list
	: tn_parameter_declaration
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $1, Znull(), 0, 0); }
	| tn_parameter_list ',' tn_parameter_declaration
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $3, $1, 0, 0); }
	;

tn_parameter_declaration
	: tn_param_type_qual_specifier tn_declarator
	{ $$ = newexprsrc(&ctx->inp->src, Edecl, $1, $2, 0, 0); }
	| tn_param_type_qual_specifier tn_abstract_declarator
	{ $$ = newexprsrc(&ctx->inp->src, Edecl, $1, $2, 0, 0); }
	| tn_param_type_qual_specifier
	{ $$ = newexprsrc(&ctx->inp->src, Edecl, $1, 0, 0, 0); }
	;

tn_param_type_qual_specifier
	: tn_param_type_specifier
	| tn_param_type_specifier type_qualifier_list
	{ $$ = $1; }
	| type_qualifier_list tn_param_type_specifier
	{ $$ = $2; }
	;

tn_param_type_specifier
	: base_list
	{ $$ = newexprsrc(&ctx->inp->src, Ebase, $1, 0, 0, 0); }
	| id
	{ $$ = newexprsrc(&ctx->inp->src, Etypedef, $1, 0, 0, 0); }
	| tn_param_struct_or_union_specifier
	| tn_param_enum_specifier
	;

tn_param_struct_or_union_specifier
	: struct_or_union id
	{ $$ = newexprsrc(&ctx->inp->src, $1, $2, 0, 0, 0); }
	;

tn_param_enum_specifier
	: ENUM id
	{ $$ = newexprsrc(&ctx->inp->src, Eenum, $2, 0, 0, 0); }
	;

tn_abstract_declarator
	: pointer
	| tn_direct_abstract_declarator
	| pointer tn_direct_abstract_declarator
	{ $$ = ptrto($1, $2); }
	;

tn_direct_abstract_declarator
	: '(' tn_abstract_declarator ')'
	{ $$ = $2; }
	| '[' ']'
	{ $$ = newexprsrc(&ctx->inp->src, Earr, 0, 0, 0, 0); }
	| '[' constant_expression ']'
	{ $$ = newexprsrc(&ctx->inp->src, Earr, 0, $2, 0, 0); }
	| tn_direct_abstract_declarator '[' ']'
	{ $$ = newexprsrc(&ctx->inp->src, Earr, $1, 0, 0, 0); }
	| tn_direct_abstract_declarator '[' constant_expression ']'
	{ $$ = newexprsrc(&ctx->inp->src, Earr, $1, $3, 0, 0); }
	| '(' ')' maybe_type_qualifier
	{ $$ = newexprsrc(&ctx->inp->src, Efun, 0, nullelist(), 0, 0); }
	| tn_direct_abstract_declarator '(' ')' maybe_type_qualifier
	{ $$ = newexprsrc(&ctx->inp->src, Efun, $1, nullelist(), 0, 0); }
	| tn_direct_abstract_declarator '(' tn_parameter_type_list ')' maybe_type_qualifier
	{ $$ = newexprsrc(&ctx->inp->src, Efun, $1, $3, 0, 0); }
	;

tn_declarator
	: pointer tn_direct_declarator
	{ $$ = ptrto($1, $2); }
	| tn_direct_declarator
	;

tn_direct_declarator
	: id
	{ $$ = $1; }
	| '(' tn_declarator ')'
	{ $$ = $2; }
	| tn_direct_declarator '[' constant_expression ']'
	{ $$ = newexprsrc(&ctx->inp->src, Earr, $1, $3, 0, 0); }
	| tn_direct_declarator '[' ']'
	{ $$ = newexprsrc(&ctx->inp->src, Earr, $1, 0, 0, 0); }
	| tn_direct_declarator '(' tn_parameter_type_list ')'
	{ $$ = newexprsrc(&ctx->inp->src, Efun, $1, $3, 0, 0); }
	| tn_direct_declarator '(' ')'
	{ $$ = newexprsrc(&ctx->inp->src, Efun, $1, nullelist(), 0, 0); }
	;

statement
	: compound_statement
	| expression_statement
	| selection_statement
	| iteration_statement
	| jump_statement
	| define_statement
	| defstx_statement
	| labeled_statement
	| global_statement
	| unquote_statement
	| mcall_statement
	;

mcall_statement
	: atid '(' argument_expression_list ')' compound_statement
	{ $$ = newexprsrc(&ctx->inp->src, Emcall, $1, invert($3), $5, 0); }
	| atid '(' ')' compound_statement
	{ $$ = newexprsrc(&ctx->inp->src, Emcall, $1, nullelist(), $4, 0); }
	| atid compound_statement
	{ $$ = newexprsrc(&ctx->inp->src, Emcall, $1, 0, $2, 0); }
	;

unquote_statement
	: SYNTAXUNQUOTE '{' statement_list '}'
	{ $$ = newexprsrc(&ctx->inp->src, Estxunquote, invert($3), 0, 0, 0); }
	;

global_statement
	: GLOBAL id_list ';'
	{ $$ = newexprsrc(&ctx->inp->src, Eglobal, invert($2), 0, 0, 0); }
	;

local
	: LOCAL id_list ';'
	{ $$ = invert($2); }
	;

local_list
	: local
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $1, nullelist(), 0, 0); }
	| local_list local
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $2, $1, 0, 0); }
	;

compound_statement
	: '{' '}'
	{
		$$ = newexprsrc(&ctx->inp->src,
				Escope,
				newexprsrc(&ctx->inp->src,
					   Eblock,
					   nullelist(),
					   nullelist(), 0, 0),
				0, 0, 0);
	}
	| '{' local_list '}'
	{
		$$ = newexprsrc(&ctx->inp->src,
				Escope,
				newexprsrc(&ctx->inp->src,
					   Eblock,
					   flatten($2),
					   nullelist(), 0, 0),
				0, 0, 0);
	}
	| '{' statement_list '}'
	{
		/* use src of first statement */
		Expr *sl;
		sl = invert($2);
		$$ = putsrc(newexpr(Escope,
				    newexpr(Eblock,
					    nullelist(),
					    sl, 0, 0),
				    0, 0, 0),
			    sl->src);
	}
	| '{' local_list statement_list '}'
	{
		/* use src of first statement */
		Expr *sl;
		sl = invert($3);
		$$ = putsrc(newexpr(Escope,
				    newexpr(Eblock,
					    flatten($2),
					    sl, 0, 0),
				    0, 0, 0),
			    sl->src);
	}
	;

statement_list_element
	: statement
	| splice_expr
	;

statement_list
	: statement_list_element
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $1, nullelist(), 0, 0); }
	| statement_list statement_list_element
	{ $$ = newexprsrc(&ctx->inp->src, Eelist, $2, $1, 0, 0); }
	;

expression_statement
	: ';'
	{ $$ = newexprsrc(&ctx->inp->src, Enil, 0, 0, 0, 0); }
	| expression ';'
	{ $$ = $1; }
	;

selection_statement
	: IF '(' expression ')' statement			%dprec 2
	{ $$ = newexprsrc(&ctx->inp->src, Eif, $3, $5, 0, 0); }
	| IF '(' expression ')' statement ELSE statement	%dprec 1
	{ $$ = newexprsrc(&ctx->inp->src, Eif, $3, $5, $7, 0); }
	| SWITCH '(' expression ')' compound_statement
	/* note: C permits body of switch to be a statement */
	{ $$ = newexprsrc(&ctx->inp->src, Eswitch, $3, $5, 0, 0); }
	;

labeled_statement
	: id ':' statement
	  { $$ = Zlabelsrc($1->src, $1, $3); }
	| CASE expression ':' statement
	  { $$ = newexprsrc(&ctx->inp->src, Ecase, $2, $4, NULL, NULL); }
	| MATCH pattern ':' statement
	  { $$ = newexprsrc(&ctx->inp->src, Ematch, $2, $4, NULL, NULL); }
	| MATCH pattern AND_OP expression ':' statement
	  { $$ = newexprsrc(&ctx->inp->src, Ematch, $2, $6, $4, NULL); }
	| DEFAULT ':' statement
	  { $$ = newexprsrc(&ctx->inp->src, Edefault, $3, NULL, NULL, NULL); }
	;

maybe_expression
	: expression
	|
	{ $$ = 0; }
	;

iteration_statement
	: WHILE '(' expression ')' statement
	{ $$ = newexprsrc(&ctx->inp->src, Ewhile, $3, $5, 0, 0); }
	| DO statement WHILE '(' expression ')' ';'
	{ $$ = newexprsrc(&ctx->inp->src, Edo, $2, $5, 0, 0); }
	| FOR '(' maybe_expression ';' maybe_expression ';' maybe_expression ')' statement
	{ $$ = newexprsrc(&ctx->inp->src, Efor, $3, $5, $7, $9); }
	;

jump_statement
	: GOTO id ';'
	{ $$ = Zgotosrc(&ctx->inp->src, $2); }
	| CONTINUE ';'
	{ $$ = newexprsrc(&ctx->inp->src, Econtinue, 0, 0, 0, 0); }
	| BREAK ';'
	{ $$ = newexprsrc(&ctx->inp->src, Ebreak, 0, 0, 0, 0); }
	| RETURN ';'
	{ $$ = newexprsrc(&ctx->inp->src, Eret, 0, 0, 0, 0); }
	| RETURN expression ';'
	{ $$ = newexprsrc(&ctx->inp->src, Eret, $2, 0, 0, 0); }
	;

defstx_statement
	: DEFSTX atid '(' arg_id_list ')' id compound_statement
	{ $$ = newexprsrc(&ctx->inp->src, Edefstx, $2, invert($4), $6, $7); }
	| DEFSTX atid '(' arg_id_list ')' compound_statement
	{ $$ = newexprsrc(&ctx->inp->src, Edefstx, $2, invert($4), 0, $6); }
	| DEFSTX atid '(' ')' id compound_statement
	{ $$ = newexprsrc(&ctx->inp->src, Edefstx, $2, nullelist(), $5, $6); }
	| DEFSTX atid '(' ')' compound_statement
	{ $$ = newexprsrc(&ctx->inp->src, Edefstx, $2, nullelist(), 0, $5); }
	| DEFSTX atid id compound_statement
	{ $$ = newexprsrc(&ctx->inp->src, Edefstx, $2, 0, $3, $4); }
	;

define
	: DEFINE
	{ $$ = Edefine; }
	| DEFLOC
	{ $$ = Edefloc; }
	;

define_statement
	: define id '(' arg_id_list ')' compound_statement
	{ $$ = putsrc(newexpr($1, $2, invert($4), $6, 0), $2->src); }
	| define id '('  ')' compound_statement
	{ $$ = putsrc(newexpr($1, $2, nullelist(), $5, 0), $2->src); }
	| define id '(' mcall_expression ')' compound_statement
	{ $$ = putsrc(newexpr($1, $2, $4, $6, 0), $2->src); }
	;

translation_unit_seq
	: translation_unit
	|
	;

translation_unit
	: external_declaration
	| translation_unit external_declaration
	;

external_declaration
	: statement		{ dotop(ctx, $1); }
	;

%%
static void
yyerror(U *ctx, const char *s)
{
	/* Some scanner rules have already signaled an error and
	   returned an error token to stop parsing. */
	if (!ctx->parse_error) {
		parseerror(ctx, (char*)s);
	}
}

/* expression trees for ambiguous forms share identifier nodes;
   separate them so that we can handle them independently. */
static void
duptickid(Expr *e)
{
	if(e == 0)
		return;
	if(e->kind == Eticke || e->kind == Etickt){
		sete1(e, copyexpr(e->e1));
		sete2(e, copyexpr(e->e2));
		return;
	}
	duptickid(e->e1);
	duptickid(e->e2);
	duptickid(e->e3);
	duptickid(e->e4);
}

/* we are here for an ambiguous expression of the form:

        (<xid>)+<expr>
        (<xid>)-<expr>
        (<xid>)*<expr>
        (<xid>)&<expr>
	(<xid>)(<expr>, ...)

   <expr> is an expression.
   <xid> is a identifier of one of two forms:

	<id>
	<id>`<id>

   <id> is an identifier.

   the underlying ambiguity is the same for all five
   forms: does the <xid> denote a type name, in which
   case the form is a cast operation, or a value, in
   which case the form is some other operation,
   superfluously parenthesized.

   the first four forms involve the four operators that
   serve both unary and binary roles.  either the form
   is intended to be a cast of the result of unary
   usage, or a binary usage with superfluous parens
   around the left operand.

   the fifth form is either a cast to the result of
   a parenthesized expression, or a call expression
   with superfluous parens around the function value.

   our policy for these cases is harsh but simple: we
   always assume the cast operation was the intended
   one.  if the user actually wanted superfluous
   parens, too bad.

   in the past we supported more a flexible
   interpretation for a limited set of forms.  for
   example, for an expression of the form:

	(dom`T)*p

   we emitted code to dynamically lookup T as a type in
   dom.  if there was type definition, we proceeded
   with a cast to a pointer dereference.  if not, we
   proceeded under the assumption that dom`T is a
   variable reference, and multiplied the result by p.

   there was no flexibility on the fifth form: we
   always assume the cast was intended.  that is
   because dom`T could not evaluate to a function value
   (but we forsee allowing this in the future).

   in the past, expressions of the form

	(T)*p

   were interpreted as multiplication.  to treat T as a
   type name, it had to be prefixed by a tick:


	(`T)*p

   this violated commonly used C syntax. the current
   policy was in put place as we were addressing this
   syntactic problem.

   the gist of this policy is that the user can always
   remove superfluous parens to achieve the desire
   binary (or call) operation.  while such parens may
   result from expansion of defensively written textual
   macros, macros based on syntactic abstraction, like
   those, do not have this problem.

   note that there is no ambiguity for cast expressions
   of any other type name form.  each of these forms is
   unambiguous:

	   (struct dom`T)*p
	   (struct T)*p
	   (dom`T*)*p
	   (T*)*p
	   (int)*p

*/

static unsigned
castcount(Expr *e)
{
	Expr *p;
	if(e == 0)
		return 0;
	switch(e->kind){
	case Ecast:
		return 1+castcount(e->e2);
	case Eelist:
		p = e;
		while(p->kind == Eelist){
			p = p->e2;
		}
	default:
		return (castcount(e->e1)
			+castcount(e->e2)
			+castcount(e->e3)
			+castcount(e->e4));
	}
}

static Expr*
castmerge(YYSTYPE ye1, YYSTYPE ye2)
{
#if 0
	Expr *cast, *other;
	if(ye1.expr->kind == Ecast){
		cast = ye1.expr;
		other = ye2.expr;
	}else if(ye2.expr->kind == Ecast){
		cast = ye2.expr;
		other = ye1.expr;
	}else{
		printf("ye1:\n");
		printexpr(ye1.expr);
		printf("\nye2:\n");
		printexpr(ye2.expr);
		yyerror(0, "unresolved ambiguity 0");
	}

	/* sanity check */
	if(cast->e1->kind != Etypename)
		yyerror(0, "unresolved ambiguity 1");
	/* cast->e2 could be any expression */
	return cast;
#else
	if(castcount(ye1.expr) > castcount(ye2.expr))
		return ye1.expr;
	else
		return ye2.expr;
#endif
}

static int
ofkind(int kind)
{
	return (kind == Esizeoft) || (kind == Esizeofe)
		|| (kind == Etypeoft) || (kind == Etypeofe);
}

static Expr*
ofmerge(YYSTYPE ye1, YYSTYPE ye2)
{
	Expr *e1, *e2;

	// Xof(dom`T)   X is "size" or "type"

	e1 = ye1.expr;
	e2 = ye2.expr;
	if(!ofkind(e1->kind) || !ofkind(e2->kind))
		yyerror(0, "unresolved ambiguity 2");

	if(e1->kind == Esizeofe || e1->kind == Etypeofe)
		duptickid(e1->e1);
	else
		duptickid(e2->e1);
	return putsrc(newexpr(Eambig, e1, e2, NULL, NULL), e1->src);
}
