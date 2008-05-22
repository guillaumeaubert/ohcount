// c.rl written by Mitchell Foral. mitchell<att>caladbolg<dott>net.

/************************* Required for every parser *************************/
#include "ragel_parser_macros.h"

// the name of the language
const char *C_LANG = "c";

// the languages entities
const char *c_entities[] = {
  "space", "comment", "string", "number", "preproc",
  "keyword", "identifier", "operator", "newline", "any"
};

// constants associated with the entities
enum {
  C_SPACE = 0, C_COMMENT, C_STRING, C_NUMBER, C_PREPROC,
  C_KEYWORD, C_IDENTIFIER, C_OPERATOR, C_NEWLINE, C_ANY
};

// do not change the following variables

// used for newlines inside patterns like strings and comments that can have
// newlines in them
#define INTERNAL_NL -1

// required by Ragel
int cs, act;
char *p, *pe, *eof, *ts, *te;

// used for calculating offsets from buffer start for start and end positions
char *buffer_start;
#define cint(c) ((int) (c - buffer_start))

// state flags for line and comment counting
int whole_line_comment;
int line_contains_code;

// the beginning of a line in the buffer for line and comment counting
char *line_start;

// state variable for the current entity being matched
int entity;

/*****************************************************************************/

%%{
  machine c;
  write data;
  include common "common.rl";

  # Line counting machine

  action c_ccallback {
    switch(entity) {
    case C_SPACE:
      ls
      break;
    case C_ANY:
      code
      break;
    case INTERNAL_NL:
      std_internal_newline(C_LANG)
      break;
    case C_NEWLINE:
      std_newline(C_LANG)
    }
  }

  c_line_comment =
    '//' @comment (
      escaped_newline %{ entity = INTERNAL_NL; } %c_ccallback
      |
      ws
      |
      (nonnewline - ws) @comment
    )*;
  c_block_comment =
    '/*' @comment (
      newline %{ entity = INTERNAL_NL; } %c_ccallback
      |
      ws
      |
      (nonnewline - ws) @comment
    )* :>> '*/';
  c_comment = c_line_comment | c_block_comment;

  c_sq_str =
    '\'' @code (
      escaped_newline %{ entity = INTERNAL_NL; } %c_ccallback
      |
      ws
      |
      [^\t '\\] @code
      |
      '\\' nonnewline @code
    )* '\'';
  c_dq_str =
    '"' @code (
      escaped_newline %{ entity = INTERNAL_NL; } %c_ccallback
      |
      ws
      |
      [^\t "\\] @code
      |
      '\\' nonnewline @code
    )* '"';
  c_string = c_sq_str | c_dq_str;

  c_line := |*
    spaces    ${ entity = C_SPACE;      } => c_ccallback;
    c_comment ${ entity = C_COMMENT;    } => c_ccallback;
    c_string  ${ entity = C_STRING;     } => c_ccallback;
    newline   ${ entity = C_NEWLINE;    } => c_ccallback;
    ^space    ${ entity = C_ANY;        } => c_ccallback;
  *|;

  # Entity machine

  action c_ecallback {
    callback(C_LANG, c_entities[entity], cint(ts), cint(te));
  }

  c_line_comment_entity = '//' (escaped_newline | nonnewline)*;
  c_block_comment_entity = '/*' any* :>> '*/';
  c_comment_entity = c_line_comment_entity | c_block_comment_entity;

  c_sq_str_entity = '\'' ([^'\\] | '\\' any)* '\'';
  c_dq_str_entity = '"' ([^"\\] | '\\' any)* '"';
  c_string_entity = c_sq_str_entity | c_dq_str_entity;

  c_number_entity = float | integer;

  c_preproc_word =
    'define' | 'elif' | 'else' | 'endif' | 'error' | 'if' | 'ifdef' |
    'ifndef' | 'import' | 'include' | 'line' | 'pragma' | 'undef' |
    'using' | 'warning';
  # TODO: find some way of making preproc match the beginning of a line.
  # Putting a 'when starts_line' conditional throws an assertion error.
  c_preproc_entity =
    '#' space* (c_block_comment_entity space*)?
      c_preproc_word (escaped_newline | nonnewline)*;

  c_identifier_entity = (alpha | '_') (alnum | '_')*;

  c_keyword_entity =
    'and' | 'and_eq' | 'asm' | 'auto' | 'bitand' | 'bitor' | 'bool' |
    'break' | 'case' | 'catch' | 'char' | 'class' | 'compl' | 'const' |
    'const_cast' | 'continue' | 'default' | 'delete' | 'do' | 'double' |
    'dynamic_cast' | 'else' | 'enum' | 'explicit' | 'export' | 'extern' |
    'false' | 'float' | 'for' | 'friend' | 'goto' | 'if' | 'inline' | 'int' |
    'long' | 'mutable' | 'namespace' | 'new' | 'not' | 'not_eq' |
    'operator' | 'or' | 'or_eq' | 'private' | 'protected' | 'public' |
    'register' | 'reinterpret_cast' | 'return' | 'short' | 'signed' |
    'sizeof' | 'static' | 'static_cast' | 'struct' | 'switch' |
    'template' | 'this' | 'throw' | 'true' | 'try' | 'typedef' | 'typeid' |
    'typename' | 'union' | 'unsigned' | 'using' | 'virtual' | 'void' |
    'volatile' | 'wchar_t' | 'while' | 'xor' | 'xor_eq';

  c_operator_entity = [+\-/*%<>!=^&|?~:;.,()\[\]{}];

  c_entity := |*
    space+              ${ entity = C_SPACE;      } => c_ecallback;
    c_comment_entity    ${ entity = C_COMMENT;    } => c_ecallback;
    c_string_entity     ${ entity = C_STRING;     } => c_ecallback;
    c_number_entity     ${ entity = C_NUMBER;     } => c_ecallback;
    c_preproc_entity    ${ entity = C_PREPROC;    } => c_ecallback;
    c_identifier_entity ${ entity = C_IDENTIFIER; } => c_ecallback;
    c_keyword_entity    ${ entity = C_KEYWORD;    } => c_ecallback;
    c_operator_entity   ${ entity = C_OPERATOR;   } => c_ecallback;
    ^space              ${ entity = C_ANY;        } => c_ecallback;
  *|;
}%%

/* Parses a string buffer with C/C++ code.
 *
 * @param *buffer The string to parse.
 * @param length The length of the string to parse.
 * @param count Integer flag specifying whether or not to count lines. If yes,
 *   uses the Ragel machine optimized for counting. Otherwise uses the Ragel
 *   machine optimized for returning entity positions.
 * @param *callback Callback function. If count is set, callback is called for
 *   every line of code, comment, or blank with 'lcode', 'lcomment', and
 *   'lblank' respectively. Otherwise callback is called for each entity found.
 */
void parse_c(char *buffer, int length, int count,
  void (*callback) (const char *lang, const char *entity, int start, int end)
  ) {
  p = buffer;
  pe = buffer + length;
  eof = pe;

  buffer_start = buffer;
  whole_line_comment = 0;
  line_contains_code = 0;
  line_start = 0;
  entity = 0;

  %% write init;
  cs = (count) ? c_en_c_line : c_en_c_entity;
  %% write exec;

  // if no newline at EOF; callback contents of last line
  if (count) { process_last_line(C_LANG) }
}
