/*
 *  The scanner definition for COOL.
 */

/*
 *  Stuff enclosed in %{ %} in the first section is copied verbatim to the
 *  output, so headers and global definitions are placed here to be visible
 * to the code in the file.  Don't remove anything that was here initially
 */
%{
#include <cool-parse.h>
#include <stringtab.h>
#include <utilities.h>
#include <assert.h>

/* The compiler assumes these identifiers. */
#define yylval cool_yylval
#define yylex  cool_yylex

/* Max size of string constants */
#define MAX_STR_CONST 1025
#define YY_NO_UNPUT   /* keep g++ happy */

extern FILE *fin; /* we read from this file */

/* define YY_INPUT so we read from the FILE fin:
 * This change makes it possible to use this scanner in
 * the Cool compiler.
 */
#undef YY_INPUT
#define YY_INPUT(buf,result,max_size) \
	if ( (result = fread( (char*)buf, sizeof(char), max_size, fin)) < 0) \
		YY_FATAL_ERROR( "read() in flex scanner failed");

char string_buf[MAX_STR_CONST]; /* to assemble string constants */
char *string_buf_ptr;

extern int curr_lineno;
extern int verbose_flag;

extern YYSTYPE cool_yylval;

/*
 *  Add Your own definitions here
 */

int comment_nesting_level; /* Depth of the comment */

/* Error values that can occur when lexing. */
#define STRING_TOO_LONG 1
#define ILLEGAL_CHARACTER 2
#define INTERMINATED_STRING 3
#define EOF_IN_STRING 4
#define EOF_IN_COMMENT 5
#define UNMATCHED_COMMENT_CLOSING 6
    
/** error_msg: Returns a suitable error message for the error id passed. */
char * error_msg(int err);
    
/*
 * append_character: Appends character to string_buf.
 *                   Returns 0 in case of success, non zero otherwise.
 */
int append_character(int ch);

%}

/*
 * Define names for regular expressions here.
 */

DARROW          =>
ASSIGN          <-
LE              <=
DIGIT           [0-9]
ALPHANUMERIC    [a-zA-Z0-9_]
WHITESPACE      [ \t\r\v\f]

%x COMMENT
%x STRING
%x INVALID_STRING

%%

<INITIAL,COMMENT>\n {
    /** Matches a new line **/
    curr_lineno++;
}

 /*
  *  Nested comments
  */

<COMMENT,INITIAL>"(*" {
    /** Matches comment openning */
    BEGIN(COMMENT);
    comment_nesting_level++;
}

<COMMENT>"*)" {
    /** Matches comment openning */
    comment_nesting_level--;
    if (!comment_nesting_level) {
        BEGIN(INITIAL);
    }
}

<COMMENT>([^*(\n]*|"*"|"(") { /** Eat up characters part of the comment **/ ; }
           
<COMMENT><<EOF>> {
    cool_yylval.error_msg = error_msg(EOF_IN_COMMENT);
    BEGIN(INITIAL);
    return (ERROR);
}

"*)" {
    cool_yylval.error_msg = error_msg(UNMATCHED_COMMENT_CLOSING);
    return (ERROR);
}

 /*
  * One line comment.
  */
"--".* {
    /** Eat up characters until end of line or EOF. **/
}

 /*
  *  The multiple-character operators.
  */
{DARROW}		{ return (DARROW); }
{ASSIGN}        { return (ASSIGN); }
{LE}            { return (LE); }
"."             { return '.'; }
"@"             { return '@'; }
"+"             { return '+'; }
"-"             { return '-'; }
"*"             { return '*'; }
"/"             { return '/'; }
"~"             { return '~'; }
"<"             { return '<'; }
"("             { return '('; }
")"             { return ')'; }
"="             { return '='; }
"{"             { return '{'; }
"}"             { return '}'; }
";"             { return ';'; }
":"             { return ':'; }
","             { return ','; }
           
 /*
  * Keywords are case-insensitive except for the values true and false,
  * which must begin with a lower-case letter.
  */
(?i:class)      { return (CLASS); }
(?i:else)       { return (ELSE); }
(?i:fi)         { return (FI); }
(?i:if)         { return (IF); }
(?i:in)         { return (IN); }
(?i:inherits)   { return (INHERITS); }
(?i:let)        { return (LET); }
(?i:loop)       { return (LOOP); }
(?i:pool)       { return (POOL); }
(?i:then)       { return (THEN); }
(?i:while)      { return (WHILE); }
(?i:case)       { return (CASE); }
(?i:esac)       { return (ESAC); }
(?i:of)         { return (OF); }
(?i:new)        { return (NEW); }
(?i:isvoid)     { return (ISVOID); }
(?i:not)        { return (NOT); }
t(?i:rue) {
    cool_yylval.boolean = true;
    return (BOOL_CONST);
}
f(?i:alse) {
    cool_yylval.boolean = false;
    return (BOOL_CONST);
}

 /*
  * String constants (C syntax)
  *
  * String tokenization starts with the encounter of the character `"`, and
  * finishes when we read either `"` (normal termination), or `\n` or EOF
  * in case of an error.
  *
  * Escape sequence \c is accepted for all characters c. Except for
  *  \n \t \b \f, the result is c.
  *
  * Null characters are not allowed inside a string constant (e.g: `\0`).
  */

 /*
  * Beginning of string.
  */
\" {
    BEGIN(STRING);
    string_buf_ptr = string_buf;
}

 /*
  * String termination.
  */
<STRING>\" {
    *string_buf_ptr = '\0';
    cool_yylval.symbol = stringtable.add_string(string_buf);
    BEGIN(INITIAL);
    return (STR_CONST);
}
 
 /*
  * Interminated strings (e.g: ends with new line or EOF.
  */
<STRING>\n {
    cool_yylval.error_msg = error_msg(INTERMINATED_STRING);
    BEGIN(INITIAL);
    return (ERROR);
}

<STRING><<EOF>> {
    cool_yylval.error_msg = error_msg(EOF_IN_STRING);
    BEGIN(INITIAL);
    return (ERROR);
}
 /* Backslash followed with new line for multiline string constants.
  * Example: "This is a string \
  *           that spans over two lines."
  */
<STRING>\\\n {
   int err = append_character('\n');
   if (err) {
        cool_yylval.error_msg = error_msg(err);
        BEGIN(INVALID_STRING);
        return (ERROR);
   }
}

 /*
  * Escaped sequences.
  */
<STRING>\\. {
    /* Escaped characters */
    int err = 0;
    switch (yytext[1]) {
    case 'n':
        err = append_character('\n');
        break;
    case 't':
        err = append_character('\t');
        break;
    case 'f':
        err = append_character('\f');
        break;
    case 'b':
        append_character('\b');
        break;
    default:
        err = append_character(yytext[1]);
        break;
    }
            
    if (err) {
        cool_yylval.error_msg = error_msg(err);
        BEGIN(INVALID_STRING);
        return (ERROR);
    }
}

 /*
  * Any other character.
  */
<STRING>. {
    int err = append_character(yytext[0]);
    if (err) {
        cool_yylval.error_msg = error_msg(err);
        BEGIN(INVALID_STRING);
        return (ERROR);
    }
}
  
 /* Terminate INVALID_STRING when encouter:
  *       - unnescaped `"`, or
  *       - End of line.
  */
            
<INVALID_STRING>\" {
    /* Closing quote */
    BEGIN(INITIAL);
}
 
<INVALID_STRING>\n {
    /* End of line */
    curr_lineno++;
    BEGIN(INITIAL);
}

<INVALID_STRING>\\\n {
    /* Escaped End of line: do not terminate yet. */
    curr_lineno++;
}
 
<INVALID_STRING>\\. { /* `\x` */}
<INVALID_STRING>. { /* Any other character */ }

           
 /*
  * Cool integers constants.
  */
{DIGIT}+ {
    cool_yylval.symbol = inttable.add_string(yytext);
    return (INT_CONST);
}

 /*
  * Type Identifiers.
  */
[A-Z]{ALPHANUMERIC}* {
    cool_yylval.symbol = idtable.add_string(yytext);
    return (TYPEID);
}

 /*
  * Object Identifiers.
  */
[a-z]{ALPHANUMERIC}* {
    cool_yylval.symbol = idtable.add_string(yytext);
    return (OBJECTID);
}

 /*
  * Whitespaces.
  */
{WHITESPACE} { /** Ignore whitespaces **/ }

 /*
  * Catch characters that cannot start any token.
  */
. {
    cool_yylval.error_msg = yytext;
    return (ERROR);
}

%%
           
char * error_msg(int err) {
    switch (err) {
    case STRING_TOO_LONG:
        return strdup("String constant too long");
    case ILLEGAL_CHARACTER:
        return strdup("String contains null character");
    case INTERMINATED_STRING:
        return strdup("Unterminated string constant");
    case EOF_IN_STRING:
            return strdup("EOF in string constant");
    case EOF_IN_COMMENT:
            return strdup("EOF in comment");
    case UNMATCHED_COMMENT_CLOSING:
           return strdup("Unmatched *)");
    default:
        return strdup("Unknown error");
    }
}
            
int append_character(int ch) {
    /* Check if illegal character */
    if (ch == '\0') {
        return ILLEGAL_CHARACTER;
    }

    size_t current_length = string_buf_ptr - string_buf;
    if (current_length + 1 < MAX_STR_CONST) {
        *string_buf_ptr++ = ch;
        return 0;
    }

    return STRING_TOO_LONG;
}
