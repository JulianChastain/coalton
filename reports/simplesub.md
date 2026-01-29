# **Implementing Algebraic Subtyping: A Comprehensive Analysis of the Simple-sub Algorithm**

> **Implementation Note:** Coalton implements algebraic subtyping based on the Simple-sub algorithm described in this document. For implementation details specific to Coalton, see [`docs/internals/design-docs/algebraic-subtyping.md`](../docs/internals/design-docs/algebraic-subtyping.md).

## **1. Introduction**

The unification of parametric polymorphism and subtyping represents one of the most enduring challenges in the design of static type systems for programming languages. For decades, the Hindley-Milner (HM) type system has served as the gold standard for functional languages, offering the powerful capability of inferring principal types—the most general possible types for a given expression—without requiring explicit type annotations from the programmer.¹ However, the core unification algorithm of HM relies on type equality, a symmetric relation that struggles to model the asymmetric nature of subtyping.² This limitation has historically forced language designers to choose between the inference convenience of HM and the expressive flexibility of subtyping, which is essential for modeling object-oriented hierarchies, extensible records, and data flows where a single expression may evaluate to heterogeneous but compatible types.³

The recent development of "Algebraic Subtyping," particularly through the work of Stephen Dolan and Alan Mycroft on the MLsub system, offered a theoretical breakthrough by demonstrating that it is possible to combine global type inference with subtyping while preserving the principal type property.³ This approach treats types as elements of a lattice equipped with union and intersection operators, allowing the inference engine to compute constraints that are effectively inequalities rather than equalities. Despite its theoretical elegance, the original formulation of MLsub relied on complex automata-theoretic machinery and a concept known as "biunification," which proved difficult for practitioners to implement and integrate into existing compiler infrastructures.⁴

This report provides an exhaustive analysis of "Simple-sub," an alternative algorithm developed by Lionel Parreaux that democratizes algebraic subtyping.⁵ Simple-sub achieves the same expressive power as MLsub—compact principal type inference with subtyping—but does so using a significantly simplified constraint propagation mechanism that eliminates the need for biunification and polar types during the constraint generation phase.⁴ By decoupling the constraint solving logic from the type simplification logic, Simple-sub essentially renders the algebraic subtyping approach accessible to a broader audience of language designers and compiler engineers.⁵ This document serves as a definitive guide to implementing Simple-sub, covering its theoretical foundations, core data structures, constraint solving algorithms, polymorphism handling, and the critical type simplification process that transforms raw constraint graphs into human-readable type signatures.

### **1.1 The Evolution of Type Inference**

To appreciate the innovation of Simple-sub, one must situate it within the broader history of type inference. The Hindley-Milner system, used in languages like OCaml, Haskell, and Elm, relies on Robinson's unification algorithm. When the type checker encounters a function application $f(x)$, it generates a constraint $f : \tau_1 \to \gamma$, where $\gamma$ is a fresh type variable representing the result.¹ If $f$ and $\tau_1$ cannot be unified—for instance, if $f$ expects an Integer but $x$ is a String—the program is rejected.

This equality-based approach is inherently bidirectional. If x is passed to a function expecting an Int, x *becomes* an Int throughout its entire scope. This rigidity precludes patterns common in dynamic languages or subtyping-based systems. For example, consider a conditional expression: if condition then 0 else "default". In standard HM, this is ill-typed because Int is not equal to String. A subtyping system, however, could infer the type of this expression as Int | String (the union of Integer and String), provided the language supports such constructs.⁴

Attempts to integrate subtyping into HM have typically involved "subtype inequalities" ($S <: T$). Early approaches often lost the principal type property, meaning the inference engine might guess a type that was correct but not the most general one, potentially rejecting valid programs later. Other approaches required local type inference or extensive annotations.² MLsub's contribution was to show that by defining types over a lattice including Top ($\top$), Bottom ($\bot$), Union ($\sqcup$), and Intersection ($\sqcap$), one could always find a principal type. Simple-sub refines this by demonstrating that the complex "biunification" of MLsub—which unifies a type with a pair of polar types—is an implementation detail that can be replaced by a directed graph of constraints.⁴

### **1.2 The Simple-sub Philosophy**

The guiding philosophy of Simple-sub is the separation of concerns between **constraint generation** and **type simplification**.⁵ In MLsub, the internal representation of types during inference is tightly coupled with their algebraic properties; the solver maintains types in a "polar" form (positive and negative) to facilitate simplification on the fly.⁴ Simple-sub, conversely, allows the internal constraint graph to grow somewhat arbitrarily during the inference pass. It is only when a type scheme is finalized (e.g., at a let binding or for the top-level output) that a sophisticated simplification pass is invoked to reduce the graph to a canonical algebraic form.⁸

This separation reduces the cognitive load on the implementer. The constraint solver becomes a relatively standard graph traversal algorithm that propagates inequalities, while the complexity of algebraic simplification—handling redundant variables, recursive cycles, and lattice absorptions—is isolated in a dedicated module.⁹ This modularity not only makes the system easier to understand (reportedly implementable in under 500 lines of Scala⁴) but also facilitates debugging and extension, such as the addition of mutable records or row polymorphism.¹⁰

## **2. Theoretical Foundations of Algebraic Subtyping**

The implementation of Simple-sub is grounded in lattice theory. Unlike standard unification, which partitions type variables into equivalence classes, algebraic subtyping positions type variables within a partial order defined by the subtyping relation ($\leq$).

### **2.1 The Subtyping Lattice**

At the heart of the system is a lattice structure bounded by two extremal types:

* **Bottom ($\bot$):** The subtype of all types. It represents the "empty" set of values, typically corresponding to computations that do not return (e.g., infinite loops or exceptions). In Simple-sub, a type variable with no lower bounds is effectively $\bot$ in a positive position.⁸
* **Top ($\top$):** The supertype of all types. It represents the set of all possible values. A type variable with no upper bounds is effectively $\top$ in a negative position.⁸

Between these bounds lie the primitive types (e.g., Int, Bool), constructed types (e.g., List[Int], Int → Bool), and record types. The lattice operations—join (union, $\sqcup$) and meet (intersection, $\sqcap$)—allow the system to express precise bounds.

* **Union Types:** Used to describe values that can be one of several types. The return type of if c then 1 else "a" is Int ∨ String.
* **Intersection Types:** Used to describe values that must satisfy multiple constraints. If a function argument x is used as an Int in one branch and a Float in another, its type is Int ∧ Float (which effectively simplifies to $\bot$ if primitives are disjoint, detecting the error).¹¹

### **2.2 Polarity and Variance**

A critical concept for implementing the constraint solver is **polarity**, which describes the direction of data flow. Polarity determines how subtyping constraints propagate through type constructors.⁸

* **Positive Polarity (+):** Corresponds to output positions, or values being *produced*. The return type of a function is in a positive position.
* **Negative Polarity (-):** Corresponds to input positions, or values being *consumed*. The argument type of a function is in a negative position.

Subtyping is **covariant** in positive positions and **contravariant** in negative positions. This means that if $S <: T$, then a function returning $S$ is a subtype of a function returning $T$ (covariance). However, a function accepting $T$ is a subtype of a function accepting $S$ (contravariance).⁵

Formally, for function types:

$$\tau_1 \to \tau_2 \leq \tau_0 \to \tau_3 \iff \tau_0 \leq \tau_1 \land \tau_2 \leq \tau_3$$

Notice the reversal: $A_2 \leq A_1$. This inversion of direction for function arguments is the primary source of complexity in flow-based type inference. In Simple-sub, this is handled by the constrain function recursively swapping argument order, which effectively wires the constraint graph backwards for inputs.⁸

### **2.3 Implicit vs. Explicit Algebra**

A distinct feature of Simple-sub is that union and intersection types are largely **emergent** properties of the constraint graph rather than first-class syntactic elements during inference.⁸

* A type variable $\alpha$ with lower bounds $\tau_1, \tau_2$ implicitly represents the union $\tau_1 \sqcup \tau_2$, because any valid instantiation of $\alpha$ must be a supertype of both $\tau_1$ and $\tau_2$.
* A type variable $\alpha$ with upper bounds $\tau_1, \tau_2$ implicitly represents the intersection $\tau_1 \sqcap \tau_2$, because $\alpha$ must be a subtype of both.

This implicit representation simplifies the solver, which only needs to manage lists of bounds. The explicit algebraic syntax ($\tau_1 \sqcup \tau_2$, $\tau_1 \sqcap \tau_2$) is generated only during the final simplification phase, where the "implicit" algebra of the graph is "reified" into a user-facing type signature.⁵

## **3. Data Structures and State Management**

The efficiency and simplicity of the Simple-sub algorithm stem directly from its data structures. Unlike the disjoint-set forests (Union-Find) used in HM, Simple-sub utilizes a directed graph where nodes are type variables and edges represent subtyping constraints.

### **3.1 The Type Hierarchy**

The type system is represented by a sealed trait (or abstract class) SimpleType, which encompasses both concrete types and type variables.

```scala
sealed trait SimpleType

// Represents a type variable in the inference graph
case class TypeVariable(state: VariableState) extends SimpleType

// Primitive types like Int, Bool, String
case class Primitive(name: String) extends SimpleType

// Function types: argument -> result
case class Function(arg: SimpleType, res: SimpleType) extends SimpleType

// Record types: { label: Type,... }
case class Record(fields: List) extends SimpleType

// Recursive types (used primarily in output/simplification)
case class Recursive(name: String, body: SimpleType) extends SimpleType
```

This definition is notably sparse. It lacks explicit Union or Intersection cases because, as noted, these are represented implicitly by the VariableState during the solving phase.⁸

### **3.2 The VariableState**

The VariableState is a mutable object that holds the constraints associated with a specific type variable. This mutability is key to the algorithm's performance, allowing constraints to be updated in-place without rebuilding the type structure.⁸

| Field | Type | Description |
| :---- | :---- | :---- |
| lowerBounds | List | A list of types $L_i$ such that $L_i \leq \alpha$. Implicitly forms the union $\bigsqcup_i L_i$. |
| upperBounds | List | A list of types $U_i$ such that $\alpha \leq U_i$. Implicitly forms the intersection $\bigsqcap_i U_i$. |
| level | Int | An integer representing the nesting depth of the variable's creation. Used for level-based generalization (let-polymorphism). |

The level field is adopted from Remy's algorithm for efficient generalization in HM systems.¹² It allows the solver to determine in constant time whether a variable is local to a specific let binding or if it belongs to an outer scope, which is crucial for determining which variables can be quantified into a polymorphic type scheme.

### **3.3 The Constraint Graph Topology**

The collection of TypeVariable nodes and their lowerBounds/upperBounds references forms a directed graph.

* An edge exists from $T$ to $\alpha$ if $T \in \alpha.\text{lowerBounds}$ (meaning $T \leq \alpha$).
* An edge exists from $\alpha$ to $T$ if $T \in \alpha.\text{upperBounds}$ (meaning $\alpha \leq T$).

Unlike HM, where unification collapses nodes ($A = B$ merges node A and node B), Simple-sub adds edges ($A \leq B$). This allows for cyclic structures to exist naturally. For example, a recursive function might induce constraints where $\alpha \leq \beta$ and $\beta \leq \alpha$. In HM, this requires a "occurs check" to prevent infinite types (unless -rectypes is enabled). In Simple-sub, such cycles are valid and represent recursive types.⁸ The solver must be designed to tolerate these cycles without entering infinite loops.

## **4. Constraint Generation and Propagation**

The core engine of Simple-sub is the constraint solving algorithm, typically implemented as a function constrain(subtype, supertype). This function is responsible for enforcing the subtyping relation and propagating the consequences through the graph.

### **4.1 The constrain Algorithm**

The constrain function takes two types, $S$ (subtype) and $T$ (supertype), and ensures that $S \leq T$.

**Step 1: Reflexivity Optimization** If $S$ and $T$ are physically the same object (reference equality), the function returns immediately. This is not just an optimization; it is a base case for termination when traversing cyclic graphs.⁸

**Step 2: Caching (Cycle Detection)**

To handle recursive types, the algorithm must maintain a cache (or "visited set") of pairs $(S, T)$ currently being processed. If constrain(S, T) is called and the pair is already in the cache, the function returns, assuming co-inductively that the constraint holds. This prevents stack overflow on inputs like constrain(A, A) where A is a recursive type structure.

**Step 3: Pattern Matching**

The algorithm inspects the structure of $S$ and $T$:

* **Primitive vs Primitive:** If both are primitives (e.g., Primitive("Int")), check if their names are equal. If not, raise a type error (e.g., "Type mismatch: Int is not a subtype of Bool").⁵
* **Function vs Function:** Given $S = A_1 \to R_1$ and $T = A_2 \to R_2$, enforcing $S \leq T$ requires enforcing $A_2 \leq A_1$ (contravariance) and $R_1 \leq R_2$ (covariance). The algorithm recursively calls constrain(A2, A1) and constrain(R1, R2). Note the swapped order for arguments.
* **Record vs Record:** Simple-sub typically implements **width subtyping** and **depth subtyping**.
  * *Width:* Every field present in $T$ must also be present in $S$. If $T$ requires field x, $S$ must provide it.
  * *Depth:* For every field x present in both, the type of x in $S$ must be a subtype of the type of x in $T$.
  * *Extension:* Snippet 10 notes that extending this to support *row variables* allows for extensible records, but the base Simple-sub handles standard structural subtyping.
* **Variable vs Type:**
  * If $S$ is a variable, add $T$ to $S$'s upperBounds.
  * If $T$ is a variable, add $S$ to $T$'s lowerBounds.
  * If both are variables, perform both operations.

### **4.2 Constraint Propagation Logic**

Simply adding a bound to a variable's state is insufficient; the change must be propagated to maintain the transitivity of the subtyping relation.

**Adding an Upper Bound ($\alpha \leq T$):**

When a type $T$ is added to the upper bounds of variable $\alpha$:

1. **Redundancy Check:** If $T$ is already in V.upperBounds, return.
2. **Insertion:** Add $T$ to V.upperBounds.
3. **Propagation:** For every type $L$ in V.lowerBounds:
   * We know $L \leq \alpha$ and now $\alpha \leq T$.
   * By transitivity, we must enforce $L \leq T$.
   * Call constrain(L, T).

**Adding a Lower Bound ($S \leq \alpha$):**

When a type $S$ is added to the lower bounds of variable $\alpha$:

1. **Redundancy Check:** If $S$ is already in V.lowerBounds, return.
2. **Insertion:** Add $S$ to V.lowerBounds.
3. **Propagation:** For every type $U$ in V.upperBounds:
   * We know $S \leq \alpha$ and $\alpha \leq U$.
   * By transitivity, we must enforce $S \leq U$.
   * Call constrain(S, U).

This propagation effectively computes the transitive closure of the subtyping relation on the fly. If we have a chain Int <= A <= B <= C <= String, adding the final link triggers a cascade of constrain calls that eventually attempts constrain(Int, String), which fails, correctly identifying the type error regardless of where in the chain the conflict arose.¹⁴

### **4.3 Error Handling and Provenance**

One challenge with propagation-based solving is that the error may occur far from the source of the constraint. For instance, constrain(L, T) in the propagation step might fail, but the user's code only explicitly established the relation $\alpha \leq T$. To provide useful error messages, a robust implementation should pass a "provenance" or "context" object through the recursive calls. This context tracks the chain of reasoning (e.g., "Constraint X implies Y, which implies Z") so that when a primitive mismatch occurs, the compiler can report the full trace of deduction.¹⁵

## **5. Polymorphism and Scope Management**

While the constraint solver handles relations between concrete types and variables, the type system must also support parametric polymorphism (generics). Simple-sub employs "Let-Polymorphism," standard in ML-family languages, where variables can be generalized at let bindings.

### **5.1 Level-Based Generalization**

To manage polymorphism efficiently, Simple-sub assigns a level to every type variable, an optimization pioneered by Didier Rémy.¹²

* **Global Counter:** The algorithm maintains a global current\_level.
* **Let Binding Entry:** When entering the right-hand side (RHS) of a let binding, current\_level is incremented.
* **Variable Creation:** Any type variable created within this scope is assigned the incremented level.
* **Let Binding Exit:** When leaving the RHS, current\_level is decremented.

A variable is considered **generic** (and thus capable of being generalized into a polymorphic scheme like $\forall\alpha.\tau$) if and only if its level is greater than the current\_level of the enclosing scope. This indicates that the variable was created locally and is not constrained by the environment outside the let binding.⁸

### **5.2 The Extrusion (Scope Check) Mechanism**

A critical complication in subtyping inference is **extrusion** (sometimes called "scope escaping"). If a locally created variable (Level $n+1$) is constrained to be a subtype of a variable from an outer scope (Level $n$), the local variable cannot be generalized. It has "leaked" into the outer environment.

In standard HM, this is handled by unifying the levels (demoting the inner variable's level). In Simple-sub, constraints are directional, so we must be more careful. The constrain function must perform an extrusion check whenever it adds a bound.

**The Logic of extrude(type, limitLevel):**

When a constraint connects a type $T$ to a variable $\alpha$, and $T$ contains variables with levels higher than $\alpha$'s level, those variables must be demoted.

1. **Traversal:** The extrude function recursively traverses the type $T$.
2. **Demotion:** If it encounters a type variable $\beta$ with $\beta.\text{level} > \text{limitLevel}$, it updates $\beta.\text{level} := \text{limitLevel}$.
3. **Recursive Update:** Crucially, if the variable's level is updated, the function must also recurse into $\beta$'s lower and upper bounds to extrude them as well. This ensures that the entire subgraph reachable from the escaping variable is anchored to the outer scope.¹³

The Extrusion Bug⁸: Early implementations of Simple-sub contained a bug where extrude would enter an infinite loop if the variable bounds contained a cycle (e.g., $A \leq B$ and $B \leq A$). If extrude blindly follows bounds, it will cycle between A and B endlessly.

* **The Fix:** Like the constrain function, extrude must maintain a visited set of type variables. If a variable has already been processed in the current extrusion pass, it should be skipped. This guarantees termination even in the presence of recursive types.

### **5.3 Instantiation of Type Schemes**

When a polymorphic variable (e.g., id with type $\forall\alpha. \alpha \to \alpha$) is used in an expression, it must be **instantiated**.

1. **Identify Generics:** Determine which variables in the type scheme are generic (Level > Definition Scope).
2. **Create Fresh Variables:** For each generic variable, create a fresh TypeVariable at the *current* execution level.
3. **Copy Structure:** Replicate the type structure, replacing references to generic variables with their fresh counterparts.
4. **Copy Bounds:** This is the most distinct step in algebraic subtyping. Unlike HM where generics are typically unconstrained, in Simple-sub, generic variables may have bounds (e.g., $\alpha \leq \text{Int}$). These bounds must also be copied and instantiated.
   * If generic $\gamma$ has lower bound $T$, the fresh $\gamma'$ must have lower bound $T'$ (where $T'$ is the instantiated version of $T$).
   * This requires a map Map[OldVar, NewVar] to ensure that the topology of the bounds graph is preserved correctly during copying.

## **6. The Type Simplification Engine**

If one inspects the constraint graph produced by the solver, it is typically a tangled web of variables. A simple identity function might result in a variable $\gamma$ with bounds pointing to intermediate variables introduced by the compiler. Presenting this to the user would be unhelpful. The **Simplification** phase is responsible for transforming this graph into a concise, readable algebraic type signature.⁵

### **6.1 Expansion to Trees**

The first step of simplification is to convert the graph into a tree structure. This process is driven by **polarity**.

**Algorithm: expand(type, polarity)**

* **Input:** A type node and a boolean polarity (True for Positive/Output, False for Negative/Input).
* **Base Case:** If the type is a primitive, return it.
* **Recursive Case:** If the type is a Function $A \to R$:
  * Return Function(expand(A,!polarity), expand(R, polarity)). Note the polarity flip for the argument.
* **Variable Case:**
  * **Positive Polarity (+):** We are interested in what the variable *produces*. This is determined by its **Lower Bounds**. The expanded type is the **Union** of the expansion of all its lower bounds.
    * If lowerBounds is empty, the result is $\bot$ (or a fresh type parameter if the variable is generic).
  * **Negative Polarity (-):** We are interested in what the variable *consumes*. This is determined by its **Upper Bounds**. The expanded type is the **Intersection** of the expansion of all its upper bounds.
    * If upperBounds is empty, the result is $\top$ (or a fresh type parameter).

This step effectively converts the implicit algebra of the graph (bounds lists) into explicit algebraic trees (Unions and Intersections).⁸

### **6.2 Co-occurrence Analysis and Redundancy Elimination**

The raw expansion often produces verbose types containing redundant variables. Simple-sub employs a "Co-occurrence Analysis" pass to prune these.

**Rule 1: Polar Variable Removal**

If a type variable $\gamma$ appears *only* in positive positions in the final type, and it is not a generic parameter constrained by the user, it provides no information to the caller. It can be replaced by its lower bounds (or $\bot$).

* *Example:* If inference produces Int → (Int ∨ 'a) and 'a is never used elsewhere, the return type is effectively just Int (assuming 'a has no other lower bounds).

**Rule 2: Sandwich Removal**

If a variable is constrained such that $T \leq \gamma \leq T$ (e.g., Int $\leq \gamma \leq$ Int), the variable acts as a meaningless indirection. The simplifier detects this topology and replaces $\gamma$ directly with $T$. This often happens when a variable unifies two identical types.

**Rule 3: Indistinguishable Variables**

If two variables $\gamma$ and $\beta$ always appear in the same polarities and share identical bounds, they are functionally equivalent. The simplifier merges them into a single variable. This reduces signatures like ('a → 'b) → 'a → 'b (where 'a and 'b are indistinguishable in constraints) to ('a → 'a) → 'a → 'a if the logic dictates identity.

### **6.3 Automata Minimization Connections**

The simplification process in Simple-sub is theoretically related to Deterministic Finite Automata (DFA) minimization. In MLsub, types are explicitly converted to automata, determinized, and minimized using algorithms like Hopcroft's Algorithm.³

* **States:** Type variables correspond to automata states.
* **Transitions:** Constructors (Function, Record) correspond to labelled transitions.
* **Minimization:** Merging equivalent states corresponds to unifying type variables that have the same behavior.

Simple-sub approximates this minimization without the full overhead of an automata library. It uses **Hash Consing** during the expansion phase.

* **Hash Consing:** Every time a type term (like Function(A, B)) is constructed, the simplifier checks a cache to see if an identical term already exists. If so, it returns the existing pointer.
* **Cyclic Unification:** By using hash consing, structurally identical recursive types are automatically unified. If A = Int → A and B = Int → B, the hash consing mechanism will eventually map them to the same memory object, effectively performing DFA minimization on the fly.⁸

## **7. Recursive Types and Canonicalization**

Recursive types pose a specific challenge for simplification. The constraint graph represents recursion as cycles (e.g., $\alpha \leq \text{Int} \to \alpha$). When expanding this to a string representation, the algorithm must detect these cycles to avoid infinite strings and to insert the appropriate mu ($\mu$) binders or as 'a syntax.

### **7.1 Cycle Detection and "Knot Tying"**

During the expand phase, the algorithm maintains a stack of visited variables.

1. If expand encounters a variable currently in the stack, a cycle is detected.
2. The algorithm marks this variable as a **Recursive Root**.
3. It returns a special RecursiveRef token.

In the final output generation:

* When the printer encounters a variable marked as a Recursive Root, it assigns it a name (e.g., 'a) and prints the body followed by as 'a (e.g., (Int → 'a) as 'a).
* When it encounters the RecursiveRef token, it simply prints the name 'a.

### **7.2 Canonicalization Strategy**

Snippet 6 and 6 highlight a "type canonicalization" algorithm added to later versions of Simple-sub. The goal is to merge recursive types that are equivalent but structurally shifted.

* *Problem:* The types $\mu\alpha. \text{Int} \to \alpha$ and $\mu\beta. \text{Int} \to \text{Int} \to \beta$ are equivalent (iso-recursive).
* *Solution:* The canonicalization algorithm typically unrolls the recursive type one level and checks for equivalence.¹⁷ By enforcing a canonical form where the recursion binder is pulled up as high as possible, the simplifier ensures that let rec bindings produce consistent, minimal signatures.

## **8. Extensions: Records and Rows**

A robust type system often requires more than just functions and primitives. Simple-sub supports records, and with some extensions, row polymorphism.

### **8.1 Structural Record Subtyping**

Base Simple-sub implements immutable records with width and depth subtyping.

* **Constraint Logic:** constrain(Record(F1), Record(F2)) succeeds if:
  1. The set of field names in $F_2$ is a subset of $F_1$ (Width).
  2. For every field l in $F_2$, constrain(F1(l), F2(l)) (Depth).

This allows passing a "large" record (many fields) to a function expecting a "small" record (fewer fields), a pattern fundamental to structural typing.

### **8.2 Extensible Records (Row Variables)**

Snippet 10 mentions an extension to Simple-sub involving **Row Variables**. Standard subtyping loses information upon "upcasting." If we cast {x:1, y:2} to {x:Int}, we lose y. If we then want to update x and return the record, we cannot say that y is still there.

To support operations like record extension or update, the lattice must be enriched with row variables that can abstract over "the rest of the fields."

* **Representation:** A record type becomes { fields | ρ } where $\rho$ is a row variable.
* **Constraint:** Constraints on records propagate to constraints on their row variables. If {x:Int | ρ1} ≤ {x:Int | ρ2}, then $\rho_1 \leq \rho_2$.
* **Complexity:** This adds significant complexity to the simplification phase, as the solver must now handle constraints on row variables, which represent sets of fields rather than single types. However, the core graph propagation logic of Simple-sub remains applicable.

## **9. Comparative Analysis**

To summarize the position of Simple-sub in the ecosystem, we compare it to HM and MLsub.

| Feature | Hindley-Milner | MLsub | Simple-sub |
| :---- | :---- | :---- | :---- |
| **Constraint Logic** | Unification ($=$) | Biunification ($\leq$) | Propagation ($\leq$) |
| **Data Structure** | Union-Find | Polar Automata | Constraint Graph |
| **Polymorphism** | Let-Generalization | Let-Generalization | Let-Generalization (Level-based) |
| **Subtyping** | None | Yes (Algebraic) | Yes (Algebraic) |
| **Simplification** | Minimal (Pruning) | Automata Minimization | Expansion + Co-occurrence Analysis |
| **Code Complexity** | Low | High | Medium |
| **Principal Types** | Yes | Yes | Yes |

Simple-sub effectively occupies the "sweet spot".⁷ It provides the subtyping capabilities of MLsub without the implementation barrier, making it feasible for projects that cannot afford the complexity of a full automata-theoretic solver.

## **10. Conclusion**

Implementing Simple-sub requires a shift in perspective from equality-based unification to graph-based constraint propagation. By maintaining a mutable graph of directional bounds and utilizing level-based extrusion to manage scope, one can build a robust inference engine that supports the rich expressiveness of algebraic subtyping.

The true innovation of Simple-sub lies not just in its solver, but in its rigorous separation of constraint generation from type simplification. The constraint solver is permissive and fast, collecting inequalities as they arise. The simplifier is sophisticated, applying polarity analysis, hash consing, and heuristic minimization to distil the chaotic constraint graph into elegant, principal type signatures.

For language designers, Simple-sub offers a blueprint for modernizing type inference. It demonstrates that features like union types, intersection types, and structural record subtyping need not come at the cost of principal types or implementation tractability. By following the architectural guidelines laid out in this report—specifically the handling of variable state, the recursive propagation logic, and the polarity-aware expansion—developers can integrate these powerful features into their own languages "for the masses."

#### **Works cited**

1. Hindley–Milner type system - Wikipedia, accessed January 28, 2026, [https://en.wikipedia.org/wiki/Hindley%E2%80%93Milner_type_system](https://en.wikipedia.org/wiki/Hindley%E2%80%93Milner_type_system)
2. Polymorphism, Subtyping, and Type Inference in MLsub - CORE, accessed January 28, 2026, [https://core.ac.uk/download/pdf/83938970.pdf](https://core.ac.uk/download/pdf/83938970.pdf)
3. The Simple Essence of Algebraic Subtyping - Infoscience, accessed January 28, 2026, [https://infoscience.epfl.ch/server/api/core/bitstreams/afe084e0-0050-4542-99c7-c499d2fe1620/content](https://infoscience.epfl.ch/server/api/core/bitstreams/afe084e0-0050-4542-99c7-c499d2fe1620/content)
4. The Simple Essence of Algebraic Subtyping: Principal Type Inference with Subtyping Made Easy | Lambda the Ultimate, accessed January 28, 2026, [http://lambda-the-ultimate.org/node/5597](http://lambda-the-ultimate.org/node/5597)
5. The Simple Essence of Algebraic Subtyping | TACO Lab, accessed January 28, 2026, [https://cse.hkust.edu.hk/~parreaux/publication/icfp20/](https://cse.hkust.edu.hk/~parreaux/publication/icfp20/)
6. LPTK/simple-sub: Alternative algorithm for algebraic subtyping. - GitHub, accessed January 28, 2026, [https://github.com/LPTK/simple-sub](https://github.com/LPTK/simple-sub)
7. Demystifying MLsub – The Simple Essence of Algebraic Subtyping - Hacker News, accessed January 28, 2026, [https://news.ycombinator.com/item?id=23956315](https://news.ycombinator.com/item?id=23956315)
8. Demystifying MLsub — the Simple Essence of Algebraic Subtyping - Well-𝚻yped Reflections, accessed January 28, 2026, [https://lptk.github.io/programming/2020/03/26/demystifying-mlsub.html](https://lptk.github.io/programming/2020/03/26/demystifying-mlsub.html)
9. Chapter 7 : Sub-algorithms (Procedures and Functions) - ops.univ-batna2.dz, accessed January 28, 2026, [https://staff.univ-batna2.dz/sites/default/files/bachir_malika/files/chapter_7_functions_procedures_0.pdf?m=1740343873](https://staff.univ-batna2.dz/sites/default/files/bachir_malika/files/chapter_7_functions_procedures_0.pdf?m=1740343873)
10. [2407.06747] Towards Algebraic Subtyping for Extensible Records - arXiv, accessed January 28, 2026, [https://arxiv.org/abs/2407.06747](https://arxiv.org/abs/2407.06747)
11. "Spurious" Type Equivalences in MLSub/Algebraic Subtyping, accessed January 28, 2026, [https://cstheory.stackexchange.com/questions/51127/spurious-type-equivalences-in-mlsub-algebraic-subtyping](https://cstheory.stackexchange.com/questions/51127/spurious-type-equivalences-in-mlsub-algebraic-subtyping)
12. 10.5.4. Let Polymorphism · Functional Programming in OCaml, accessed January 28, 2026, [https://courses.cs.cornell.edu/cs3110/2021sp/textbook/interp/letpoly.html](https://courses.cs.cornell.edu/cs3110/2021sp/textbook/interp/letpoly.html)
13. When Subtyping Constraints Liberate - Well-𝚻yped Reflections, accessed January 28, 2026, [https://lptk.github.io/superf-paper](https://lptk.github.io/superf-paper)
14. CONSTRAINT LOGIC PROGRAMMING: A SURVEY, accessed January 28, 2026, [https://courses.grainger.illinois.edu/cs522/sp2016/ConstraintLogicProgrammingASurvey.pdf](https://courses.grainger.illinois.edu/cs522/sp2016/ConstraintLogicProgrammingASurvey.pdf)
15. A practical introduction to Constraint Programming | by VeepeeTech - Medium, accessed January 28, 2026, [https://medium.com/vptech/a-practical-introduction-to-constraint-programming-2037c91833ba](https://medium.com/vptech/a-practical-introduction-to-constraint-programming-2037c91833ba)
16. Subtyping Recursive Types modulo Associative Commutative Products - Cambium, accessed January 28, 2026, [http://cambium.inria.fr/~fpottier/publis/dicosmo-pottier-remy-tlca05.pdf](http://cambium.inria.fr/~fpottier/publis/dicosmo-pottier-remy-tlca05.pdf)
17. Recursive types - Lambda the Ultimate, accessed January 28, 2026, [http://lambda-the-ultimate.org/node/5352](http://lambda-the-ultimate.org/node/5352)
