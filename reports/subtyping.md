# The Dichotomy of Abstraction: An Exhaustive Analysis of Subtyping and Type Classes

> **Implementation Note:** Coalton unifies type classes with algebraic subtyping. Type class constraints are integrated with the Simple-sub algorithm's constraint propagation. For implementation details, see [`docs/internals/design-docs/algebraic-subtyping.md`](../docs/internals/design-docs/algebraic-subtyping.md).

## 1. Introduction: The Fundamental Schism in Type Theory

The history of programming language theory is, to a significant degree, a history of the struggle to balance rigid correctness with flexible extensibility. At the heart of this struggle lies the concept of **polymorphism**—the ability of code to operate on values of different types. While the ultimate objective of polymorphism is unified—to enable the creation of generic, reusable, and robust software components—the mechanisms developed to achieve it have diverged into two dominant paradigms: **Subtyping** (often referred to as inclusion polymorphism) and **Type Classes** (a form of ad-hoc polymorphism via parametric overloading).

These two paradigms represent fundamentally different philosophical answers to the question: *How should we treat unknown data?*

Subtyping, the bedrock of Object-Oriented Programming (OOP), answers this question with a hierarchy of identity. It posits that types are related by an ontological "is-a" relationship. If a Cat is an Animal, then code written for an Animal should function correctly for a Cat due to the principle of substitutability. This model emphasizes encapsulation and the bundling of data with behavior, where the dispatch mechanism is inherent to the object itself.¹

Type Classes, the cornerstone of functional languages like Haskell and increasingly adopted in systems languages like Rust, answer the question with a dictionary of capabilities. It posits that types are related by a teleological "can-do" relationship. A type Int is not a Show, but it *possesses* a Show instance that provides the capability to convert it to a string. This model emphasizes the separation of data and behavior and enables retroactive extensibility, where the evidence of capability is passed alongside the data rather than residing within it.¹

This report provides an exhaustive, expert-level analysis of these two systems. It dissects their theoretical underpinnings in lambda calculus and category theory, their concrete implementation details (from vtables and thunks to dictionary passing and fat pointers), their profound impact on software architecture (coupling, the Expression Problem, modularity), and the modern convergence seen in languages like Rust, Swift, and Scala that attempt to unify these disparate worlds.

### 1.1 The Evolution of Polymorphism

To understand the current state of the art, one must appreciate the historical trajectory. Subtyping emerged from the simulation-oriented languages of the 1960s, most notably Simula 67, which introduced the concept of classes and inheritance to model physical objects. This lineage evolved through Smalltalk and C++ into the dominant Java/C# model of the 1990s. In contrast, type classes were introduced in the late 1980s by Wadler and Blott as a solution to the problem of ad-hoc polymorphism (operator overloading) in standard ML, eventually becoming the defining feature of Haskell.⁵

The divergence was not merely syntactic but semantic. Subtyping focused on the structure of data and the compatibility of interfaces (structural or nominal), while type classes focused on the algebraic properties of operations (associativity, commutativity) and the separation of implementation from definition. Today, the lines are blurring, but the fundamental trade-offs in performance, memory layout, and architectural coupling remain distinct and critical for system designers to understand.

---

## 2. Theoretical Foundations and Taxonomy

To analyze the practical implications of subtyping versus type classes, one must first dismantle the theoretical structures that define them. Cardelli and Wegner's taxonomy of polymorphism remains the standard framework for this analysis, situating both mechanisms within the broader context of type theory.

### 2.1 The Polymorphism Taxonomy

Polymorphism is generally categorized into **Universal** and **Ad-hoc** varieties. Universal polymorphism implies that a function works uniformly on an infinite range of types, whereas ad-hoc polymorphism implies distinct behaviors for distinct types.

| Category | Type | Description | Mechanism | Theoretical Basis |
| :---- | :---- | :---- | :---- | :---- |
| **Universal** | **Parametric** | Functions work on *any* type uniformly without inspecting the structure (e.g., length of a list). | Type erasure, Monomorphization. | System F ($\Lambda$) |
|  | **Inclusion (Subtyping)** | Functions work on a range of types related by containment ($S <: T$). | Dynamic Dispatch, Vtables. | System F$_{<:}$ (Bounded Quantification) |
| **Ad-hoc** | **Overloading** | Same function name maps to different implementations based on argument types. | Static resolution at compile time. | Syntactic sugar (Context-dependent) |
|  | **Coercion** | Values are implicitly converted to the expected type. | Runtime/Compile-time casting. | Type conversion rules |

**Subtyping** falls squarely under Inclusion Polymorphism. It is defined by the subset relation. If $S$ is a subtype of $T$ ($S <: T$), then the set of values denoted by $S$ is a subset of the values denoted by $T$. In type-theoretic terms, this guarantees that any term of type $S$ can be safely used in any context where a term of type $T$ is expected.¹

**Type Classes** are a sophisticated form of **Ad-hoc Polymorphism**, specifically **Parametric Overloading**. Unlike simple overloading (which is resolved strictly at compile time based on fixed signatures), type classes allow for polymorphism over *open* sets of types. A function `sort :: Ord a => [a] -> [a]` is parametric over `a`, but constrained by the `Ord` type class. It does not work for *all* types, only those for which an `Ord` evidence exists. This blends the genericity of parametric polymorphism with the specificity of ad-hoc overloading.¹

### 2.2 The Lambda Cube: System F vs. System F$_{<:}$

The theoretical distinction is rigorous when viewed through the lens of the **Lambda Cube**, a framework for classifying type systems.

* **Subtyping (System F$_{<:}$):** This extends System F (the polymorphic lambda calculus) with a subtyping relation. Quantifiers are bounded: $\forall \alpha <: T$. This expresses that the type variable $\alpha$ is not universally abstract but is constrained to be a subtype of $T$. The semantics rely on **subsumption**: if a term $e$ has type $S$ and $S <: T$, then $e$ also has type $T$. Crucially, the term $e$ does not necessarily change; it is simply viewed through a different lens.²
* **Type Classes (System F$_{\omega}$ with Predicates):** Type classes are often modeled in an extension of System F where constraints are treated as predicates or evidence requirements. A function with a class constraint $C \Rightarrow$ is theoretically transformed into a function that accepts a type $\tau$ *and* a value representing the proof that $C\ \tau$ holds. This transformation, known as **evidence passing**, means that the term $e$ of type $\tau$ does *not* inherently satisfy the constraint; it requires an external witness (the dictionary) to be passed alongside it.⁵

### 2.3 Behavioral Correctness: LSP vs. Algebraic Laws

The "correctness" of an abstraction is governed by fundamentally different principles in each paradigm.

#### Subtyping: The Liskov Substitution Principle (LSP)

The theoretical correctness of subtyping is governed by the Liskov Substitution Principle (LSP), introduced by Barbara Liskov. It shifts subtyping from a purely syntactic definition (do the method signatures match?) to a **behavioral** one.

Formally, LSP states:

*Let $\phi(x)$ be a property provable about objects $x$ of type $T$. Then $\phi(y)$ should be true for objects $y$ of type $S$ where $S <: T$.*⁹

This implies that a subtype must not only match the interface of the supertype (covariance of return types, contravariance of arguments) but must also adhere to the **contracts**—invariants, preconditions, and postconditions—of the supertype.

* **Preconditions:** A subtype cannot strengthen preconditions (it cannot demand more than the parent).
* **Postconditions:** A subtype cannot weaken postconditions (it cannot guarantee less than the parent).
* **Invariants:** The subtype must preserve all invariants of the supertype.

In practice, most object-oriented languages (Java, C#) enforce only syntactic subtyping. Behavioral subtyping is left to the discipline of the programmer. This disconnect leads to the "Fragile Base Class" problem, where changes in the parent implementation inadvertently break assumptions made by subclasses, or vice versa.¹²

#### Type Classes: Algebraic Laws and Evidence

Type classes operate closer to the realm of algebra. A type class defines a set of operations and, crucially, a set of **laws** that implementations should obey. For example, a Monoid type class requires:

1. An associative binary operation (`mappend` or `<>`).
2. An identity element (`mempty`).

The laws are:

$$
\begin{aligned}
x \diamond (y \diamond z) &= (x \diamond y) \diamond z \quad \text{(Associativity)} \\
\mathit{mempty} \diamond x &= x \quad \text{(Left Identity)} \\
x \diamond \mathit{mempty} &= x \quad \text{(Right Identity)}
\end{aligned}
$$

Unlike LSP, which focuses on the relationship between two different types (parent and child), type class laws focus on the internal consistency of a single type's operations. The compiler usually cannot enforce these laws (except in dependently typed languages like Idris), but the **coherence** and optimizations of the system depend on them. For instance, a compiler can reorder parallel reductions only if the associativity law holds.¹⁴

---

## 3. Structural vs. Nominal Typing Mechanisms

The distinction between subtyping and type classes is often conflated with the distinction between **Nominal** and **Structural** typing. While correlated, they are orthogonal axes of language design that interact with polymorphism in complex ways.

### 3.1 Nominal Subtyping (Java, C#, C++)

In nominal systems, subtyping is explicit and based on identity. A type $S$ is a subtype of $T$ if and only if it explicitly declares so (e.g., `class Dog extends Animal`).

* **Safety via Intent:** The primary advantage is that the programmer declares the relationship, preventing accidental subtyping where structures match by coincidence but semantics differ (e.g., a Cowboy drawing a gun vs. a Shape drawing a circle).¹⁶
* **Rigidity:** The disadvantage is rigidity. You cannot make a third-party class implement your interface without a wrapper (Adapter pattern). This leads to the "retroactive implementation" problem, where extending the behavior of existing types requires significant boilerplate.¹⁷

### 3.2 Structural Subtyping (TypeScript, Go, OCaml)

In structural systems, subtyping is implicit. $S <: T$ if $S$ contains all the methods/fields required by $T$. This is often colloquially called "Duck Typing" in dynamic languages, but in static languages (like Go's interfaces), it is checked at compile time.

* **Flexibility:** A type automatically satisfies any interface it matches. This allows for powerful post-hoc abstraction, where an interface can be defined *after* the concrete types are written.¹⁸
* **Accidental Conformance:** The risk is that types may match syntactically but not semantically, leading to incorrect behavior. Furthermore, purely structural systems can make refactoring difficult, as changing a method name in one interface may inadvertently break subtyping relationships in distant parts of the codebase.²⁰

### 3.3 Type Classes: The Middle Ground

Type classes behave distinctly. Like nominal typing, instances are explicit (you must write `instance Show Int`). However, like structural typing, the definition of the type `Int` and the definition of the interface `Show` are decoupled. The connection (the instance) can be defined in a separate module. This provides the safety of nominal typing (explicit intent) with the flexibility of structural typing (retroactive extension).⁷

---

## 4. Mechanisms of Dispatch: The Implementation Layer

The theoretical differences manifest physically in how the computer executes the code. The choice between subtyping and type classes dictates memory layout, instruction count, and optimization potential. This section provides a low-level analysis of the **Virtual Method Table (vtable)** versus **Dictionary Passing**.

### 4.1 Subtyping: The Virtual Method Table (vtable)

In languages like C++ and Java, inclusion polymorphism is implemented via **dynamic dispatch** using vtables.

#### Memory Layout and Dispatch

Every object of a polymorphic class contains a hidden pointer (the vptr) to a table of function pointers (the vtable).

* **Object Layout:** `[ vptr | field_1 | field_2 | ... ]`
* **Vtable Layout:** `[ method_A_addr | method_B_addr | ... ]`

When a method `obj.method_A()` is called:

1. **Load Object:** The program holds the pointer to obj.
2. **Load Vptr:** It dereferences the object header to load the vptr.
3. **Calculate Offset:** It applies a fixed compile-time offset to the vptr to find the address of method_A in the table.
4. **Load Address:** It loads the function address from the table.
5. **Indirect Jump:** It performs an indirect jump (CALL) to that address.²²

#### Performance Implications

* **Indirection:** The dispatch requires multiple memory loads (load vptr, load function address).
* **Cache Misses:** If the vtable is not in the CPU cache (L1/L2), this causes a stall. In tight loops iterating over heterogeneous objects, vtables can thrash the instruction cache because the CPU cannot predict the target of the jump effectively.
* **Inlining Barrier:** The compiler typically cannot inline the function call because the target address is unknown until runtime. This blocks subsequent optimizations (constant folding, loop unrolling), which are often more significant than the call overhead itself.²⁵
* **Space Overhead:** Every object carries a vptr (typically 8 bytes on 64-bit systems). For small objects (e.g., a complex number or a point), this overhead is significant (doubling or tripling the size).²⁸

#### Thunks and Multiple Inheritance

In C++, multiple inheritance complicates this picture. If a class C inherits from A and B, the object layout must contain parts of A and B. When casting `C*` to `B*`, the compiler must apply a pointer adjustment (thunk) to point to the B sub-object. This adds additional instructions and complexity to the dispatch mechanism compared to single-inheritance models like Java.³⁰

### 4.2 Type Classes: Dictionary Passing (Haskell)

Haskell compiles type classes by transforming them into standard data types, a process known as **dictionary passing**.

#### The Transformation

A type class declaration is transformed into a **record type** (the dictionary).

```haskell
-- Source
class Eq a where
  (==) :: a -> a -> Bool

-- Core Representation (approximate)
data EqDict a = EqDict { eq_func :: a -> a -> Bool }
```

A function with a class constraint is transformed into a function that takes the dictionary as an extra argument.

```haskell
-- Source
allEqual :: Eq a => [a] -> Bool

-- Core Representation
allEqual :: EqDict a -> [a] -> Bool
```

#### Dispatch Mechanics

There is no vptr in the data values. A list of integers `[1, 2, 3]` contains strictly integers. The "evidence" of how to compare them (the `EqDict Int`) is passed separately to the `allEqual` function.

* **Decoupled:** The data remains "plain." Polymorphism does not alter the memory layout of the data.
* **Dictionary Passing Overhead:** Passing dictionaries adds function arguments. In deeply nested calls, this can involve threading multiple dictionaries through the stack.
* **Optimization (Specialization):** GHC heavily relies on **specialization** (monomorphization). If the compiler knows `allEqual` is called with `Int`, it inlines the `EqDict Int` and eliminates the dictionary lookup entirely, resulting in code identical to a specialized C loop. This is a crucial performance optimization that makes high-level Haskell abstractions performant.⁵

### 4.3 Rust: The Hybrid "Fat Pointer" Model

Rust bridges the gap using **Traits** (Type Classes) but offers two usage modes: **Static Dispatch** (Monomorphization) and **Dynamic Dispatch** (Trait Objects).

#### Static Dispatch (impl Trait)

Like C++ templates, this generates a specialized copy of the function for every concrete type used.

* **Cost:** Zero runtime cost (no vtable lookup).
* **Benefit:** Full inlining and optimization.
* **Downside:** Binary bloat (code duplication).³³

#### Dynamic Dispatch (dyn Trait)

When a unified type is needed (e.g., a `Vec<Box<dyn Animal>>`), Rust uses **Trait Objects**. Unlike C++, Rust does *not* store the vtable pointer in the object. It uses **Fat Pointers**.

A reference `&dyn Trait` consists of two words (128 bits on 64-bit systems):

1. **Data Pointer:** Address of the concrete data.
2. **Vtable Pointer:** Address of the vtable for that specific Trait implementation.

**Layout Comparison:**

* **C++ (Thin Pointer):** Object = `[vptr | data]`. Pointer = `[obj_addr]`.
* **Rust (Fat Pointer):** Object = `[data]`. Pointer = `[obj_addr | vptr_addr]`.

**Implications:**

* **Data Purity:** Rust structs don't pay the storage cost of polymorphism unless they are actively used as trait objects. A `u64` is just 8 bytes, even if it implements 50 traits.
* **Cache Locality:** Fat pointers can increase register pressure (passing two registers instead of one) and cache pressure (pointers are twice as large). However, they avoid the "double indirection" of loading the vtable from the object header; the vtable address is available immediately in the reference.²⁸

### 4.4 Swift: Witness Tables

Swift employs a similar mechanism called **Protocol Witness Tables (PWT)**. When a type conforms to a protocol, a PWT is generated containing the function implementations.

* **Value Witness Table (VWT):** Swift also generates a VWT which describes the *lifecycle* of the type (how to allocate, copy, destroy, and deallocate it). This allows Swift to handle polymorphism over **Value Types** (structs) without boxing them, distinct from Java's requirement to box `int` to `Integer` for generics.³⁶

---

## 5. The Expression Problem and Extensibility

The **Expression Problem**, formulated by Philip Wadler, serves as the ultimate litmus test for these systems. It asks: *Can we define a data abstraction that is extensible in both its representations (new types) and its behaviors (new operations) without recompiling existing code and while retaining static type safety?*³⁹

### 5.1 The Matrix of Extensibility

Imagine a matrix where **rows** are Types (e.g., Integer, Boolean) and **columns** are Operations (e.g., toString, evaluate).

|  | toString | evaluate | serialize (New) |
| :---- | :---- | :---- | :---- |
| **Integer** | impl | impl | impl |
| **Boolean** | impl | impl | impl |
| **NewType** | ??? | ??? | ??? |

#### Subtyping (OO Approach)

* **Adding Types (Rows):** **Easy.** Just create a new class NewType and implement the interface methods. No existing code needs modification.
* **Adding Operations (Columns):** **Hard.** To add `serialize`, you must modify the base interface/class. This breaks all existing subclasses (the Fragile Base Class problem) or requires recompilation of the entire hierarchy.
  * *Workaround:* The **Visitor Pattern**. This inverts the structure to make adding operations easy, but makes adding types hard (you must modify the Visitor interface). It essentially simulates type classes within OO, but clumsily and with significant boilerplate.⁴¹

#### Type Classes (Functional Approach)

* **Adding Operations (Columns):** **Easy.** Define a new type class `Serialize` and provide instances for existing types. The original types do not need to be touched.
* **Adding Types (Rows):** **Context-Dependent.**
  * If using **Algebraic Data Types (ADTs)** (e.g., `data Expr = Lit Int | Add Expr Expr`), adding a new case `Sub` requires modifying the datatype definition, breaking all existing pattern matches.
  * If using **Tagless Final** or **Object Algebras** (see below), adding types becomes easy.
* **The "Orphan Instance" Problem:** While adding operations is "easy," the interaction between libraries can create orphan instances, where coherence is threatened if multiple libraries define the same instance (discussed in Section 6).⁴⁰

### 5.2 Solutions and Hybrid Approaches

The Expression Problem has driven significant innovation in uniting these paradigms.

#### Object Algebras and Tagless Final

**Object Algebras** (OO) and **Tagless Final** (FP) are isomorphic solutions to the Expression Problem. They abstract over the constructors of the data types, treating them as interfaces.

* **Tagless Final (Haskell):**

```haskell
class ExprSym repr where
  lit :: Int -> repr
  add :: repr -> repr -> repr

eval :: ExprSym repr => repr -> Int
view :: ExprSym repr => repr -> String
```

Here, `repr` is abstract. To add a new type (e.g., `Sub`), one simply defines a new type class `SubSym` extending `ExprSym`. To add a new operation, one defines a new interpreter function. This allows full extensibility in both dimensions.⁴⁷

#### C# Extension Types and Shapes

C# attempts to mitigate OO rigidity with Extension Methods (adding operations to existing types). However, traditional extension methods are static and do not participate in polymorphism. The new **"Shapes"** or **"Extension Types"** proposals aim to introduce true type-class-like behavior, allowing extensions to implement interfaces retroactively, effectively creating "witness structs" under the hood.⁵¹

---

## 6. Coherence, Modularity, and The Orphan Rule

One of the most nuanced and critical distinctions between implementations of type classes is the concept of **Coherence**. This section explores the trade-offs between global uniqueness (Haskell) and local flexibility (Scala).

### 6.1 Definition of Coherence

A type system is **coherent** if every valid typing derivation for a program leads to the same dynamic semantics. In the context of type classes: *For any given type T and type class C, there must be exactly one instance `C T` in the entire program.*⁵⁴

Why does this matter? Consider a `Set` data structure that relies on an `Ord` (ordering) constraint.

```haskell
insert :: Ord a => a -> Set a -> Set a
```

If one part of the program uses an `Ord` instance that sorts ascending, and another part uses an instance that sorts descending, passing a `Set` between them leads to corruption (the binary search tree invariants are violated). Coherence guarantees that the `Set` always sees the "same" `Ord` regardless of where the code is executed.⁵⁵

### 6.2 The Haskell Approach: Global Uniqueness

Haskell enforces strict global coherence. An instance is either defined in the module defining the Type, the module defining the Class, or it is an **Orphan Instance**.

* **Orphan Instance:** An instance `C T` defined in a module M that defines neither C nor T.
* **The Rule:** GHC discourages orphans because they threaten coherence. If two libraries define the same orphan instance (e.g., `JSON` for `Int`), the program cannot link.
* **Pros:** Strong reasoning guarantees. Data structures like `Set` and `Map` work correctly and predictably.
* **Cons:** Anti-modular. You cannot use a library's type with another library's class unless one of them depends on the other, or you define an orphan (risking conflict). The standard workaround is "newtype wrappers" (`newtype MyInt = MyInt Int`), which treats the type as distinct, allowing a new instance. This incurs ergonomic overhead but zero runtime cost.⁵⁵

### 6.3 The Scala Approach: Local Coherence (Incoherence)

Scala's **implicits** (and Scala 3's **givens**) relax this. Instances are searched for in the **implicit scope**. This scope includes the companion objects of the type and class (like Haskell), but also the *lexical scope* of the call site.

* **Pros:** Maximum flexibility. You can define a local `Ord` for integers that sorts modulo 10 just for one function call. You can have multiple JSON serializers for the same object in different contexts.
* **Cons:** Loss of global uniqueness. Passing a `Set` created with one implicit to a function expecting a different implicit can lead to runtime errors or logical bugs. It requires vigilance from the programmer to avoid "implicit hell" where the resolution logic becomes opaque.⁵⁴

### 6.4 The Rust Approach: The Orphan Rule

Rust adopts a middle ground enforced by the compiler's **Orphan Rules**. You can implement a trait T for a type S only if:

1. You defined T in your crate (local trait).
2. OR, you defined S in your crate (local type).

* **Implication:** You cannot implement a foreign trait for a foreign type (e.g., you cannot implement `serde::Serialize` for `chrono::DateTime` if you are in a third crate `my_app`).
* **Workaround:** The "Newtype" pattern (`struct MyWrapper(ForeignType)`).
* **Rationale:** Ensures coherence (no two crates can introduce conflicting instances) while allowing reasonable extensibility. It prevents the "action at a distance" problems of Scala while maintaining the safety of Haskell.⁶⁴

---

## 7. Software Engineering Implications: Coupling and Architecture

The choice between subtyping and type classes fundamentally shapes software architecture, dictating how components are coupled and how systems evolve.

### 7.1 Coupling Types

* **Inheritance Coupling:** Subtyping creates tight coupling. A subclass depends on the layout and implementation details of the parent. This is the **Fragile Base Class** problem. Changes to the base class (e.g., changing a private field's usage) can ripple down the hierarchy and break subclasses. This violates encapsulation because the subclass often relies on the *implementation* of the parent, not just its interface.¹³
* **Identity Coupling:** In nominal typing, a method `void process(User u)` is coupled to the *identity* of the `User` class. It cannot accept a `MockUser` unless `MockUser` inherits from `User` (which might be impossible if `User` is a final class in a library).

### 7.2 Decoupling via Type Classes

Type classes introduce **Capability Coupling**. A function `fn process<T: UserLike>(u: T)` is coupled only to the *capability* described by `UserLike`.

* **Retroactive Modeling:** This is the "killer feature" of type classes. You can define a `JSON` type class and implement it for `String`, `Int`, and `Files`—types that were defined long before your JSON library existed. In an OO world, you cannot make the standard `String` class implement your new `IJson` interface. You are forced to write Adapter wrappers (`JsonString(String s)`), adding allocation overhead and boilerplate. Type classes allow the data to remain naked while adopting new behaviors.²⁰

### 7.3 Testing and Mocking

Type classes simplify testing. Instead of using reflection-based mocking frameworks (like Mockito) to override the behavior of concrete classes, you simply define a `Mock` struct and implement the necessary traits. The function under test, being generic over the trait, accepts the mock indistinguishably from the real object. This promotes a design where components interact through contracts rather than concrete implementations.⁷

---

## 8. Language Ecosystem Comparisons

### 8.1 C++: The Kitchen Sink

C++ supports both paradigms but keeps them separate.

* **Subtyping:** Virtual functions (`virtual`) provide classic inclusion polymorphism.
* **Type Classes:** **Concepts** (introduced in C++20) act as compile-time type classes for templates. They constrain template parameters, improving error messages and enabling overloading. However, they resolve entirely at compile time (monomorphization) and do not natively support dynamic dispatch (you can't have a `std::vector<Concept>`). C++ developers must manually choose between `virtual` (runtime) and template (compile-time) polymorphism, often resulting in complex metaprogramming.²³

### 8.2 Java and C#: Nominal Evolution

Java and C# started purely with nominal subtyping. They have slowly evolved:

* **Generics:** Added parametric polymorphism (but with type erasure in Java, reification in C#).
* **Default Interface Methods:** Allowed adding operations to interfaces without breaking implementors (partial solution to Expression Problem).
* **Proposals:** C#'s **"Extension Everything"** and **"Roles/Shapes"** proposals aim to allow implementing interfaces for existing classes (retroactive implementation). This would effectively bring type classes to C#, implemented via "witness structs" (dictionaries) under the hood. This represents a significant shift towards the type class philosophy within the enterprise OO world.⁵¹

### 8.3 Haskell: The Purest

Haskell treats type classes as the primary mechanism. There is no subtyping in the OO sense (no `Dog <: Animal`).

* **Existentials:** To get dynamic dispatch (heterogeneous lists), Haskell uses existential quantification (`data Showable = forall a. Show a => Pack a`). This boxes the value and the dictionary, equivalent to a vtable-object pair. This forces the programmer to be explicit about when they are opting into dynamic behavior.⁵

### 8.4 Rust: The Pragmatic Unification

Rust is arguably the most successful unification of the concepts.

* **Traits** serve as both Interfaces (for dynamic dispatch via `dyn Trait`) and Type Classes (for static dispatch via bounds `T: Trait`).
* **Coherence:** Enforced via orphan rules.
* **Memory:** Explicit choice between `Box<dyn Trait>` (fat pointer, heap) and `T: Trait` (monomorphized, stack). This forces the programmer to be aware of the cost of polymorphism, making it ideal for systems programming.²⁸

---

## 9. Conclusion

The dichotomy between subtyping and type classes is dissolving. Modern language design acknowledges that neither approach is sufficient in isolation.

**Subtyping** excels at modeling **open sets of data types** that share a common closed interface (e.g., UI widgets, where any widget must `draw()` but new widgets are constantly added). Its mechanism, the vtable, is efficient for uniform interface access but suffers from rigidity, coupling, and the fragile base class problem.

**Type Classes** excel at modeling **open sets of operations** over closed or open data types (e.g., Serialization, Equality, Ordering). Their mechanism, dictionary passing (or monomorphization), offers superior performance (via inlining), architectural flexibility (retroactive modeling), and rigorous correctness (via coherence and laws), but introduces challenges in binary size and modularity (orphan instances).

The future lies in **hybrid systems**. Languages like Rust and Swift, and proposals for C#, demonstrate that providing a unified syntax that can lower to either vtables (for dynamic needs) or dictionaries/monomorphization (for static needs) allows developers to choose the right trade-off for their specific domain. The "Expression Problem" is no longer a blocker, but a design choice: do you prioritize extending types or extending operations? The modern systems programmer, equipped with the understanding of these paradigms, is empowered to handle both with precision and safety.

---

## Works Cited

1. Polymorphism (computer science) - Wikipedia, accessed January 26, 2026, [https://en.wikipedia.org/wiki/Polymorphism_(computer_science)](https://en.wikipedia.org/wiki/Polymorphism_(computer_science))
2. Subtyping - Wikipedia, accessed January 26, 2026, [https://en.wikipedia.org/wiki/Subtyping](https://en.wikipedia.org/wiki/Subtyping)
3. Ad-hoc polymorphism and type classes | by Sinisa Louc - Medium, accessed January 26, 2026, [https://medium.com/@sinisalouc/ad-hoc-polymorphism-and-type-classes-442ae22e5342](https://medium.com/@sinisalouc/ad-hoc-polymorphism-and-type-classes-442ae22e5342)
4. Are typeclasses essential? - haskell - Stack Overflow, accessed January 26, 2026, [https://stackoverflow.com/questions/25855507/are-typeclasses-essential](https://stackoverflow.com/questions/25855507/are-typeclasses-essential)
5. Implementing, and Understanding Type Classes - okmij.org, accessed January 26, 2026, [https://okmij.org/ftp/Computation/typeclass.html](https://okmij.org/ftp/Computation/typeclass.html)
6. Haskell Typeclasses vs. C++ Classes - Hacker News, accessed January 26, 2026, [https://news.ycombinator.com/item?id=15490415](https://news.ycombinator.com/item?id=15490415)
7. When is it preferable to use ad hoc polymorphism over subtype polymorphism? - Reddit, accessed January 26, 2026, [https://www.reddit.com/r/scala/comments/n7c3be/when_is_it_preferable_to_use_ad_hoc_polymorphism/](https://www.reddit.com/r/scala/comments/n7c3be/when_is_it_preferable_to_use_ad_hoc_polymorphism/)
8. Subtyping Constrained Types - Yale FLINT Group, accessed January 26, 2026, [https://flint.cs.yale.edu/trifonov/papers/subcon.pdf](https://flint.cs.yale.edu/trifonov/papers/subcon.pdf)
9. Liskov substitution principle - Wikipedia, accessed January 26, 2026, [https://en.wikipedia.org/wiki/Liskov_substitution_principle](https://en.wikipedia.org/wiki/Liskov_substitution_principle)
10. SOLID Design Principles Explained: The Liskov Substitution Principle with Code Examples, accessed January 26, 2026, [https://stackify.com/solid-design-liskov-substitution-principle/](https://stackify.com/solid-design-liskov-substitution-principle/)
11. A behavioral notion of subtyping - CMU School of Computer Science, accessed January 26, 2026, [https://www.cs.cmu.edu/~wing/publications/LiskovWing94.pdf](https://www.cs.cmu.edu/~wing/publications/LiskovWing94.pdf)
12. What is an example of the Liskov Substitution Principle? - Stack Overflow, accessed January 26, 2026, [https://stackoverflow.com/questions/56860/what-is-an-example-of-the-liskov-substitution-principle](https://stackoverflow.com/questions/56860/what-is-an-example-of-the-liskov-substitution-principle)
13. Fragile base class - Wikipedia, accessed January 26, 2026, [https://en.wikipedia.org/wiki/Fragile_base_class](https://en.wikipedia.org/wiki/Fragile_base_class)
14. What is the relation between type classes, laws that they should follow and mathematical properties? - Learn - Haskell Discourse, accessed January 26, 2026, [https://discourse.haskell.org/t/what-is-the-relation-between-type-classes-laws-that-they-should-follow-and-mathematical-properties/10157](https://discourse.haskell.org/t/what-is-the-relation-between-type-classes-laws-that-they-should-follow-and-mathematical-properties/10157)
15. Definitive guide on when to use typeclasses? : r/haskell - Reddit, accessed January 26, 2026, [https://www.reddit.com/r/haskell/comments/1j0awq/definitive_guide_on_when_to_use_typeclasses/](https://www.reddit.com/r/haskell/comments/1j0awq/definitive_guide_on_when_to_use_typeclasses/)
16. Type Systems: Structural vs. Nominal typing explained | by Jamie Kyle - Medium, accessed January 26, 2026, [https://medium.com/@thejameskyle/type-systems-structural-vs-nominal-typing-explained-56511dd969f4](https://medium.com/@thejameskyle/type-systems-structural-vs-nominal-typing-explained-56511dd969f4)
17. Integrating Nominal and Structural Subtyping - CMU School of Computer Science, accessed January 26, 2026, [https://www.cs.cmu.edu/~aldrich/papers/ecoop08.pdf](https://www.cs.cmu.edu/~aldrich/papers/ecoop08.pdf)
18. Subtypes - Omniverse, accessed January 26, 2026, [https://www.gaohongnan.com/computer_science/type_theory/01-subtypes.html](https://www.gaohongnan.com/computer_science/type_theory/01-subtypes.html)
19. Type systems: nominal vs. structural, explicit vs. implicit - Software Engineering Stack Exchange, accessed January 26, 2026, [https://softwareengineering.stackexchange.com/questions/181154/type-systems-nominal-vs-structural-explicit-vs-implicit](https://softwareengineering.stackexchange.com/questions/181154/type-systems-nominal-vs-structural-explicit-vs-implicit)
20. By typeclasses, do you mean structural typing a.k.a. duck typing a.k.a. Go-style... | Hacker News, accessed January 26, 2026, [https://news.ycombinator.com/item?id=11103769](https://news.ycombinator.com/item?id=11103769)
21. Difference between Type Class and Algebraic data types - Stack Overflow, accessed January 26, 2026, [https://stackoverflow.com/questions/74961117/difference-between-type-class-and-algebraic-data-types](https://stackoverflow.com/questions/74961117/difference-between-type-class-and-algebraic-data-types)
22. Ad-hoc, Inclusion, Parametric & Coercion Polymorphisms - GeeksforGeeks, accessed January 26, 2026, [https://www.geeksforgeeks.org/dsa/ad-hoc-inclusion-parametric-coercion-polymorphisms/](https://www.geeksforgeeks.org/dsa/ad-hoc-inclusion-parametric-coercion-polymorphisms/)
23. Virtual method table - Wikipedia, accessed January 26, 2026, [https://en.wikipedia.org/wiki/Virtual_method_table](https://en.wikipedia.org/wiki/Virtual_method_table)
24. Understanding Virtual Tables in C++ - pablo arias, accessed January 26, 2026, [https://pabloariasal.github.io/2017/06/10/understanding-virtual-tables/](https://pabloariasal.github.io/2017/06/10/understanding-virtual-tables/)
25. [Research] `if` statement vs vtable lookup for speed? : r/cpp_questions - Reddit, accessed January 26, 2026, [https://www.reddit.com/r/cpp_questions/comments/xef0fl/research_if_statement_vs_vtable_lookup_for_speed/](https://www.reddit.com/r/cpp_questions/comments/xef0fl/research_if_statement_vs_vtable_lookup_for_speed/)
26. Why is execution-time method resolution faster than compile-time resolution?, accessed January 26, 2026, [https://stackoverflow.com/questions/2925132/why-is-execution-time-method-resolution-faster-than-compile-time-resolution](https://stackoverflow.com/questions/2925132/why-is-execution-time-method-resolution-faster-than-compile-time-resolution)
27. In general, is it worth using virtual functions to avoid branching?, accessed January 26, 2026, [https://softwareengineering.stackexchange.com/questions/301510/in-general-is-it-worth-using-virtual-functions-to-avoid-branching](https://softwareengineering.stackexchange.com/questions/301510/in-general-is-it-worth-using-virtual-functions-to-avoid-branching)
28. C++20 & Rust on Static vs Dynamic Generics - Reddit, accessed January 26, 2026, [https://www.reddit.com/r/rust/comments/fmo4zb/c20_rust_on_static_vs_dynamic_generics/](https://www.reddit.com/r/rust/comments/fmo4zb/c20_rust_on_static_vs_dynamic_generics/)
29. Were fat pointers a good idea? : r/rust - Reddit, accessed January 26, 2026, [https://www.reddit.com/r/rust/comments/8ckfdb/were_fat_pointers_a_good_idea/](https://www.reddit.com/r/rust/comments/8ckfdb/were_fat_pointers_a_good_idea/)
30. Memory layout of a class under multiple or virtual inheritance and the vtable(s)?, accessed January 26, 2026, [https://stackoverflow.com/questions/28521242/memory-layout-of-a-class-under-multiple-or-virtual-inheritance-and-the-vtables](https://stackoverflow.com/questions/28521242/memory-layout-of-a-class-under-multiple-or-virtual-inheritance-and-the-vtables)
31. How does GHC handle typeclass and instance in core? - Stack Overflow, accessed January 26, 2026, [https://stackoverflow.com/questions/54508647/how-does-ghc-handle-typeclass-and-instance-in-core](https://stackoverflow.com/questions/54508647/how-does-ghc-handle-typeclass-and-instance-in-core)
32. Understanding Haskell Features Through Their Desugaring - Serokell, accessed January 26, 2026, [https://serokell.io/blog/haskell-to-core](https://serokell.io/blog/haskell-to-core)
33. Monorphization vs Dynamic Dispatch - help - The Rust Programming Language Forum, accessed January 26, 2026, [https://users.rust-lang.org/t/monorphization-vs-dynamic-dispatch/65593](https://users.rust-lang.org/t/monorphization-vs-dynamic-dispatch/65593)
34. Rust Static vs. Dynamic Dispatch - SoftwareMill, accessed January 26, 2026, [https://softwaremill.com/rust-static-vs-dynamic-dispatch/](https://softwaremill.com/rust-static-vs-dynamic-dispatch/)
35. Rust Deep Dive: Borked Vtables and Barking Cats – Geo's Notepad - GitHub Pages, accessed January 26, 2026, [https://geo-ant.github.io/blog/2023/rust-dyn-trait-objects-fat-pointers/](https://geo-ant.github.io/blog/2023/rust-dyn-trait-objects-fat-pointers/)
36. At runtime, how does Swift know which implementation to use? - Stack Overflow, accessed January 26, 2026, [https://stackoverflow.com/questions/38332616/at-runtime-how-does-swift-know-which-implementation-to-use](https://stackoverflow.com/questions/38332616/at-runtime-how-does-swift-know-which-implementation-to-use)
37. Why does Swift need witness tables? - Software Engineering Stack Exchange, accessed January 26, 2026, [https://softwareengineering.stackexchange.com/questions/331971/why-does-swift-need-witness-tables](https://softwareengineering.stackexchange.com/questions/331971/why-does-swift-need-witness-tables)
38. Where does the term witness table come from? - Compiler - Swift Forums, accessed January 26, 2026, [https://forums.swift.org/t/where-does-the-term-witness-table-come-from/54334](https://forums.swift.org/t/where-does-the-term-witness-table-come-from/54334)
39. The Expression Problem, Gracefully - PDXScholar, accessed January 26, 2026, [https://pdxscholar.library.pdx.edu/cgi/viewcontent.cgi?article=1141&context=compsci_fac](https://pdxscholar.library.pdx.edu/cgi/viewcontent.cgi?article=1141&context=compsci_fac)
40. Expression problem - Wikipedia, accessed January 26, 2026, [https://en.wikipedia.org/wiki/Expression_problem](https://en.wikipedia.org/wiki/Expression_problem)
41. Sum Types, Visitors, and the Expression Problem, accessed January 26, 2026, [https://koerbitz.me/posts/Sum-Types-Visitors-and-the-Expression-Problem.html](https://koerbitz.me/posts/Sum-Types-Visitors-and-the-Expression-Problem.html)
42. The Expression Problem - Danny Velasquez, accessed January 26, 2026, [https://www.dannyvelasquez.com/posts/the-expression-problem/](https://www.dannyvelasquez.com/posts/the-expression-problem/)
43. Understanding the need of Visitor Pattern - Software Engineering Stack Exchange, accessed January 26, 2026, [https://softwareengineering.stackexchange.com/questions/333692/understanding-the-need-of-visitor-pattern](https://softwareengineering.stackexchange.com/questions/333692/understanding-the-need-of-visitor-pattern)
44. 8.11 The Expression Problem and the Visitor Pattern - Programming 2, accessed January 26, 2026, [https://prog2.de/book/sec-java-expr-problem.html](https://prog2.de/book/sec-java-expr-problem.html)
45. Is "Solving the Expression Problem" worth the bother? : r/haskell - Reddit, accessed January 26, 2026, [https://www.reddit.com/r/haskell/comments/4gjf7g/is_solving_the_expression_problem_worth_the_bother/](https://www.reddit.com/r/haskell/comments/4gjf7g/is_solving_the_expression_problem_worth_the_bother/)
46. Solving the expression problem with Object Algebras and Tagless Interpreters : r/haskell, accessed January 26, 2026, [https://www.reddit.com/r/haskell/comments/2stmt6/solving_the_expression_problem_with_object/](https://www.reddit.com/r/haskell/comments/2stmt6/solving_the_expression_problem_with_object/)
47. Extensibility for the Masses - UT Austin Computer Science, accessed January 26, 2026, [https://www.cs.utexas.edu/~wcook/projects/oa/oa.pdf](https://www.cs.utexas.edu/~wcook/projects/oa/oa.pdf)
48. Is it ok to use Tagless Final (Object Algebras) on coalgebras? - Stack Overflow, accessed January 26, 2026, [https://stackoverflow.com/questions/58025604/is-it-ok-to-use-tagless-final-object-algebras-on-coalgebras](https://stackoverflow.com/questions/58025604/is-it-ok-to-use-tagless-final-object-algebras-on-coalgebras)
49. My favorite solution to the expression problem is the tagless-final style. It ca... - Hacker News, accessed January 26, 2026, [https://news.ycombinator.com/item?id=24558062](https://news.ycombinator.com/item?id=24558062)
50. Free Monad vs Tagless Final | by Anthony Garo - Medium, accessed January 26, 2026, [https://medium.com/@agaro1121/free-monad-vs-tagless-final-623f92313eac](https://medium.com/@agaro1121/free-monad-vs-tagless-final-623f92313eac)
51. .NET Futures: Type Classes and Extensions - InfoQ, accessed January 26, 2026, [https://www.infoq.com/news/2017/04/DotNet-Type-Classes/](https://www.infoq.com/news/2017/04/DotNet-Type-Classes/)
52. Official C# language proposal for type shapes (type classes / traits) : r/programming - Reddit, accessed January 26, 2026, [https://www.reddit.com/r/programming/comments/5vusjx/official_c_language_proposal_for_type_shapes_type/](https://www.reddit.com/r/programming/comments/5vusjx/official_c_language_proposal_for_type_shapes_type/)
53. New And Proposed Changes For C# 13 - June 5, 2024 - Peter Ritchie's Blog, accessed January 26, 2026, [https://blog.peterritchie.com/posts/new-and-proposed-changes-in-csharp-13-2024-jun-5](https://blog.peterritchie.com/posts/new-and-proposed-changes-in-csharp-13-2024-jun-5)
54. Does Scala guarantee coherence in the presence of implicits? - Stack Overflow, accessed January 26, 2026, [https://stackoverflow.com/questions/54954291/does-scala-guarantee-coherence-in-the-presence-of-implicits](https://stackoverflow.com/questions/54954291/does-scala-guarantee-coherence-in-the-presence-of-implicits)
55. Type classes: confluence, coherence and global uniqueness - ezyang's blog, accessed January 26, 2026, [https://blog.ezyang.com/2014/07/type-classes-confluence-coherence-global-uniqueness/](https://blog.ezyang.com/2014/07/type-classes-confluence-coherence-global-uniqueness/)
56. Type class - Wikipedia, accessed January 26, 2026, [https://en.wikipedia.org/wiki/Type_class](https://en.wikipedia.org/wiki/Type_class)
57. The trouble with typeclasses - Paul Chiusano, accessed January 26, 2026, [https://pchiusano.github.io/2018-02-13/typeclasses.html](https://pchiusano.github.io/2018-02-13/typeclasses.html)
58. On the State of Coherence in the Land of Type Classes - arXiv, accessed January 26, 2026, [https://www.arxiv.org/pdf/2502.20546](https://www.arxiv.org/pdf/2502.20546)
59. Boston Haskell: Edward Kmett - Type Classes vs. the World - Reddit, accessed January 26, 2026, [https://www.reddit.com/r/haskell/comments/2w4ctt/boston_haskell_edward_kmett_type_classes_vs_the/](https://www.reddit.com/r/haskell/comments/2w4ctt/boston_haskell_edward_kmett_type_classes_vs_the/)
60. Type Classes: When To Use Them, When To Avoid Them - John A De Goes, accessed January 26, 2026, [https://degoes.net/articles/when-to-typeclass](https://degoes.net/articles/when-to-typeclass)
61. Scala 3: Givens vs Implicits Quickly Explained | Rock the JVM, accessed January 26, 2026, [https://rockthejvm.com/articles/scala-3-givens-vs-implicits](https://rockthejvm.com/articles/scala-3-givens-vs-implicits)
62. Implicit vs Scala 3's Given - Alexandru Nedelcu, accessed January 26, 2026, [https://alexn.org/blog/2022/05/11/implicit-vs-scala-3-given/](https://alexn.org/blog/2022/05/11/implicit-vs-scala-3-given/)
63. Allow Typeclasses to Declare Themselves Coherent · Issue #4 · lampepfl/dotty-feature-requests - GitHub, accessed January 26, 2026, [https://github.com/lampepfl/dotty-feature-requests/issues/4](https://github.com/lampepfl/dotty-feature-requests/issues/4)
64. The naming conventions of Rust and Haskell - Reddit, accessed January 26, 2026, [https://www.reddit.com/r/rust/comments/f4ove1/the_naming_conventions_of_rust_ans_haskell/](https://www.reddit.com/r/rust/comments/f4ove1/the_naming_conventions_of_rust_ans_haskell/)
65. Orphan rules - #7 by pcwalton - ideas (deprecated) - Rust Internals, accessed January 26, 2026, [https://internals.rust-lang.org/t/orphan-rules/1322/7](https://internals.rust-lang.org/t/orphan-rules/1322/7)
66. Orphan rules - ideas (deprecated) - Rust Internals, accessed January 26, 2026, [https://internals.rust-lang.org/t/orphan-rules/1322](https://internals.rust-lang.org/t/orphan-rules/1322)
67. What are the technical reasons for the orphan rule? : r/rust - Reddit, accessed January 26, 2026, [https://www.reddit.com/r/rust/comments/b4a4fu/what_are_the_technical_reasons_for_the_orphan_rule/](https://www.reddit.com/r/rust/comments/b4a4fu/what_are_the_technical_reasons_for_the_orphan_rule/)
68. (PDF) The Role of Inheritance in the Maintainability of Object-Oriented Systems, accessed January 26, 2026, [https://www.researchgate.net/publication/2533946_The_Role_of_Inheritance_in_the_Maintainability_of_Object-Oriented_Systems](https://www.researchgate.net/publication/2533946_The_Role_of_Inheritance_in_the_Maintainability_of_Object-Oriented_Systems)
69. Implementation inheritance is bad - the fragile base class problem - GitHub, accessed January 26, 2026, [https://github.com/Dobiasd/articles/blob/master/implementation_inheritance_is_bad_-_the_fragile_base_class_problem.md](https://github.com/Dobiasd/articles/blob/master/implementation_inheritance_is_bad_-_the_fragile_base_class_problem.md)
70. Is Fragile Base Class the only reason why "inheritance breaks encapsulation"?, accessed January 26, 2026, [https://stackoverflow.com/questions/51002008/is-fragile-base-class-the-only-reason-why-inheritance-breaks-encapsulation](https://stackoverflow.com/questions/51002008/is-fragile-base-class-the-only-reason-why-inheritance-breaks-encapsulation)
71. Adapter pattern - Wikipedia, accessed January 26, 2026, [https://en.wikipedia.org/wiki/Adapter_pattern](https://en.wikipedia.org/wiki/Adapter_pattern)
72. Dumb question but what is the difference between generics and typeclasses? - Reddit, accessed January 26, 2026, [https://www.reddit.com/r/scala/comments/9s4dhb/dumb_question_but_what_is_the_difference_between/](https://www.reddit.com/r/scala/comments/9s4dhb/dumb_question_but_what_is_the_difference_between/)
73. Core Developer Skills: Coupling - PMI, accessed January 26, 2026, [https://www.pmi.org/disciplined-agile/core-developer-skills/core-developer-skill-coupling](https://www.pmi.org/disciplined-agile/core-developer-skills/core-developer-skill-coupling)
74. C++ Concepts vs Rust Traits vs Haskell Typeclasses vs Swift Protocols - Conor Hoekstra - ACCU 2021 : r/cpp - Reddit, accessed January 26, 2026, [https://www.reddit.com/r/cpp/comments/nxxz2f/c_concepts_vs_rust_traits_vs_haskell_typeclasses/](https://www.reddit.com/r/cpp/comments/nxxz2f/c_concepts_vs_rust_traits_vs_haskell_typeclasses/)
75. Exploration: Shapes and Extensions · dotnet csharplang · Discussion #164 - GitHub, accessed January 26, 2026, [https://github.com/dotnet/csharplang/discussions/164](https://github.com/dotnet/csharplang/discussions/164)
76. Is C#'s Extension Types feature called Extension Members now? : r/dotnet - Reddit, accessed January 26, 2026, [https://www.reddit.com/r/dotnet/comments/1n1bdib/is_cs_extension_types_feature_called_extension/](https://www.reddit.com/r/dotnet/comments/1n1bdib/is_cs_extension_types_feature_called_extension/)
77. What is the difference between type class dependence in haskell and sub typing in OOP?, accessed January 26, 2026, [https://stackoverflow.com/questions/51055359/what-is-the-difference-between-type-class-dependence-in-haskell-and-sub-typing-i](https://stackoverflow.com/questions/51055359/what-is-the-difference-between-type-class-dependence-in-haskell-and-sub-typing-i)
78. Is class dictionary passing the result of a implementation choice or theoretical necessity. : r/haskell - Reddit, accessed January 26, 2026, [https://www.reddit.com/r/haskell/comments/16x9v54/is_class_dictionary_passing_the_result_of_a/](https://www.reddit.com/r/haskell/comments/16x9v54/is_class_dictionary_passing_the_result_of_a/)
79. Rust Dynamic Dispatching deep-dive | by Marco Amann | Digital Frontiers - Medium, accessed January 26, 2026, [https://medium.com/digitalfrontiers/rust-dynamic-dispatching-deep-dive-236a5896e49b](https://medium.com/digitalfrontiers/rust-dynamic-dispatching-deep-dive-236a5896e49b)
80. Are traits similar to Haskells Type Classes? : r/rust - Reddit, accessed January 26, 2026, [https://www.reddit.com/r/rust/comments/1e0fuon/are_traits_similar_to_haskells_type_classes/](https://www.reddit.com/r/rust/comments/1e0fuon/are_traits_similar_to_haskells_type_classes/)
