# Errors Design

Use one concrete transported diagnostic type everywhere, not a family of error subtypes.

## Core Model

struct ParseError
  phase::ErrorPhase
  domain::ErrorDomain
  code::UInt8
  token::String
  detail::String
  sites::Vector{ErrorSite}
end

struct ErrorSite
  phase::ErrorPhase
  domain::ErrorDomain
  subject::String
end

struct ParseFailure
  consumed::Int
  error::ParseError
end

## Layers

- Parse pass returns ParseResult = Result{ParseSuccess{S}, ParseFailure}
- Complete pass returns Result{T,ParseError}
- Public argparse should eventually return T or throw a public exception built from ParseError

## Key Idea

- ParseFailure is parse-control data
- ParseError is the semantic diagnostic payload
- consumed stays outside ParseError

## Error Axes

- ErrorPhase: ParsePhase, ValuePhase, CompletePhase
- ErrorDomain: one domain per parser/value-parser family
Examples: D_Argument, D_Option, D_Object, D_Multiple, D_IntegerVal, D_UUIDVal
- code::UInt8: parser-local error code within that domain

## Per-Parser Design

- each parser/value parser defines its own local enum
- examples:
  - ArgumentErrCode
  - OptionErrCode
  - IntegerValCode
- these are immediately encoded into the common concrete ParseError
- do not transport parser-specific structs or unions

## Why

- keeps trimming stable
- avoids large unions
- preserves parser-specific failure semantics
- gives a single renderer boundary

## How Nested Errors Behave

- parser-originated failures create their own domain/code
- nested value-parser failures should usually be preserved, not rewritten
- outer parsers annotate errors with context using sites

## Example

- integer(max=10) on "42" emits:
  - phase = ValuePhase
  - domain = D_IntegerVal
  - code = INT_AboveMax
- option("--port", integer(...)) adds a site like:
  - ErrorSite(ParsePhase, D_Option, "--port")

## Rule For Complete Pass

- do not transform errors into a different type family
- create new ParseErrors for completion-only failures
- otherwise bubble existing ParseErrors upward
- optionally enrich them with more sites/context

## Examples Of Completion-Originated Errors

- missing required field in object
- too few / too many in multiple
- missing positional argument at completion

## Recommended Helper Style

option_error(code::OptionErrCode; token="", detail="", subject="")
integer_error(code::IntegerValCode; token="", detail="")
push_site(err, phase, domain, subject)

## Public API Direction

- ParseError remains internal/intermediate diagnostic payload
- public argparse should eventually return parsed value or throw a package exception rendered from ParseError

## One-Line Principle

Parser-specific enums at the construction layer, one concrete ParseError at the transport layer.

# Examples

Add parser-local enums and helpers like this.

@enum ErrorPhase::UInt8 begin
  ParsePhase
  ValuePhase
  CompletePhase
end

@enum ErrorDomain::UInt8 begin
  D_Argument
  D_Option
  D_Object
  D_Multiple
  D_IntegerVal
end

struct ErrorSite
  phase::ErrorPhase
  domain::ErrorDomain
  subject::String
end

struct ParseError
  phase::ErrorPhase
  domain::ErrorDomain
  code::UInt8
  token::String
  detail::String
  sites::Vector{ErrorSite}
end

## Example Parser-Local Enums

@enum ArgumentErrCode::UInt8 begin
  ARG_ExpectedArgument
  ARG_GotOption
  ARG_Duplicate
end

@enum OptionErrCode::UInt8 begin
  OPT_NoMatch
  OPT_MissingValue
  OPT_Duplicate
end

@enum ObjectErrCode::UInt8 begin
  OBJ_UnexpectedToken
  OBJ_MissingField
end

@enum MultipleErrCode::UInt8 begin
  MULT_TooFew
  MULT_TooMany
end

@enum IntegerValCode::UInt8 begin
  INT_Invalid
  INT_BelowMin
  INT_AboveMax
end

## Example Helpers

mkerror(
  phase::ErrorPhase,
  domain::ErrorDomain,
  code::UInt8;
  token::String = "",
  detail::String = "",
  sites::Vector{ErrorSite} = ErrorSite[],
) = ParseError(phase, domain, code, token, detail, sites)

push_site(err::ParseError, phase::ErrorPhase, domain::ErrorDomain, subject::String) =
  ParseError(err.phase, err.domain, err.code, err.token, err.detail,
      [err.sites..., ErrorSite(phase, domain, subject)])

## Parser-Specific Constructors

argument_error(code::ArgumentErrCode; token="", detail="", subject="") =
  mkerror(ParsePhase, D_Argument, UInt8(code);
      token,
      detail,
      sites = isempty(subject) ? ErrorSite[] : [ErrorSite(ParsePhase, D_Argument, subject)],
  )

option_error(code::OptionErrCode; token="", detail="", subject="") =
  mkerror(ParsePhase, D_Option, UInt8(code);
      token,
      detail,
      sites = isempty(subject) ? ErrorSite[] : [ErrorSite(ParsePhase, D_Option, subject)],
  )

object_error(code::ObjectErrCode; token="", detail="", subject="") =
  mkerror(CompletePhase, D_Object, UInt8(code);
      token,
      detail,
      sites = isempty(subject) ? ErrorSite[] : [ErrorSite(CompletePhase, D_Object, subject)],
  )

multiple_error(code::MultipleErrCode; token="", detail="", subject="") =
  mkerror(CompletePhase, D_Multiple, UInt8(code);
      token,
      detail,
      sites = isempty(subject) ? ErrorSite[] : [ErrorSite(CompletePhase, D_Multiple, subject)],
  )

integer_error(code::IntegerValCode; token="", detail="") =
  mkerror(ValuePhase, D_IntegerVal, UInt8(code); token, detail)

## Example Usage In Parsers

return parseerr(ctx, option_error(
  OPT_MissingValue;
  token = tok,
  subject = p.names[1],
  detail = "option requires a value",
))

return typedErr(integer_error(
  INT_AboveMax;
  token = input,
  detail = string(iv.max),
))

## Example Of Preserving Nested Value Errors And Annotating

valerr = integer_error(INT_AboveMax; token="70000", detail="65535")
outerr = push_site(valerr, ParsePhase, D_Option, "--port")

That lets the renderer produce something like:

--port: value 70000 is above the maximum 65535

without losing that the originating domain was D_IntegerVal.