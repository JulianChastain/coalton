\input cwebmac

\def\title{The Coalton Compiler}
\def\author{The Coalton Contributors}

@*Introduction.

This document presents the complete source code and documentation for
the Coalton compiler, a statically-typed, strict, pure functional
programming language that compiles to Common Lisp.

Coalton provides Haskell-like features---algebraic data types, type classes,
type inference, and pattern matching---while leveraging the Common Lisp
ecosystem. Code written in Coalton can seamlessly interoperate with
existing Common Lisp libraries.

@*1Organization.

The compiler is organized into several major subsystems:

\begingroup\parskip=0pt
\item{1.} {\bf Algorithms} --- foundational data structures and algorithms
including strongly connected components (for dependency analysis) and
persistent maps (for environments)
\item{2.} {\bf Parser} --- lexical analysis, parsing, and renaming of
Coalton source code
\item{3.} {\bf Type Checker} --- kind checking, type inference, type class
resolution, and constraint solving
\item{4.} {\bf Code Generator} --- translation to Common Lisp, optimization
passes, and code emission
\item{5.} {\bf Analysis} --- static analysis including pattern exhaustiveness
checking and unused variable detection
\item{6.} {\bf Runtime} --- runtime support structures for compiled code
\endgroup

Each subsystem is documented in its own section with detailed explanations
of the algorithms, data structures, and design decisions involved.

@*1About This Document.

This book is written in the literate programming style using CLWEB, a
system for Common Lisp inspired by Donald Knuth's WEB. In literate
programming, documentation and code are interwoven in a single source
file. The source can be:

\begingroup\parskip=0pt
\item{$\bullet$} {\bf Tangled} to extract executable Common Lisp code
\item{$\bullet$} {\bf Woven} to produce typeset documentation (this PDF)
\endgroup

The authoritative source is the collection of \.{.clw} files in the
\.{web/compiler/} directory. Generated \.{.lisp} files should not be
edited directly.

@*1Building Coalton.

To build the compiler from literate sources:

$$\vbox{\halign{\.{#}\hfil\cr
;; Load CLWEB and Coalton system\cr
(ql:quickload :coalton-web)\cr
\cr
;; For interactive development:\cr
(clweb:load-web "web/compiler/algorithm")\cr}}$$

To generate this documentation:

$$\vbox{\halign{\.{#}\hfil\cr
;; Generate TeX file\cr
(clweb:weave "web/compiler/coalton-book")\cr
\cr
;; Then run:\cr
pdflatex coalton-book.tex\cr}}$$

@*Algorithms.

The algorithm module provides foundational data structures used throughout
the compiler.

@i algorithm.clw

@*Parser.

{\it This section will be populated in Phase 4 of the literate conversion.}

The parser transforms Coalton source text into an abstract syntax tree.
It handles:
\begingroup\parskip=0pt
\item{$\bullet$} Lexical analysis and token stream generation
\item{$\bullet$} S-expression parsing via Eclector
\item{$\bullet$} AST construction
\item{$\bullet$} Name resolution and renaming
\endgroup

@*Type Checker.

{\it This section will be populated in Phases 2--3 of the literate conversion.}

The type checker implements Coalton's Hindley--Milner type system with
extensions for type classes and functional dependencies. Major components
include:

\begingroup\parskip=0pt
\item{$\bullet$} Kind system for classifying types
\item{$\bullet$} Type representation and substitutions
\item{$\bullet$} Unification algorithm
\item{$\bullet$} Type class and instance handling
\item{$\bullet$} Constraint solving and context reduction
\item{$\bullet$} Type inference for expressions and patterns
\endgroup

@*Code Generation.

{\it This section will be populated in Phase 5 of the literate conversion.}

The code generator translates type-checked Coalton code to Common Lisp.
It includes several optimization passes:

\begingroup\parskip=0pt
\item{$\bullet$} Monomorphization of polymorphic functions
\item{$\bullet$} Constant propagation
\item{$\bullet$} Function inlining
\item{$\bullet$} Type specialization
\endgroup

@*Analysis.

{\it This section will be populated in Phase 5 of the literate conversion.}

Static analysis passes check for potential issues:

\begingroup\parskip=0pt
\item{$\bullet$} Pattern exhaustiveness checking
\item{$\bullet$} Unused variable detection
\item{$\bullet$} Under-applied value detection
\endgroup

@*Runtime.

{\it This section will be populated in Phase 5 of the literate conversion.}

Runtime support structures for compiled Coalton code.

@*Index.
