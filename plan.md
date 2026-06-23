The issue is that in `_commitcmd`, `commithelp` is the first statement and is immediately followed by an assignment (`message_file = ...`). My current logic (from Option 2) sees a statement followed by an assignment and assumes it is the field help for that assignment.

To fix this while respecting that "the description can only be the very first statement", we need to clarify how to resolve the ambiguity if the struct starts with exactly one statement before the first assignment.

**Example 1:**
```julia
@parser struct CommitCmd
    commithelp
    message_file = commit_message_source
end
```
You want `commithelp` to be the **description**.

**Example 2:**
```julia
@parser struct Config
    "Host help"
    host = option("--host")
end
```
Do you want `"Host help"` to be the **description** of the struct, or the **field help** for `host`?

If `"Host help"` should be the field help, then we have a rule conflict: how does the macro know `commithelp` is a description but `"Host help"` is field help?
Is it because `commithelp` is a variable (Symbol) and field helps are always Strings? 
Or is it because the very first statement is *always* the description (meaning Example 2's `"Host help"` would become the description, not the field help)?

**Proposed Logic:**
1. The **description** can *only* be the 1st statement in the struct.
2. The **footer** can *only* be the last statement in the struct.
3. For any assignment (`field = parser`), if the immediately preceding statement is a **String** (or a string macrocall like `doc"..."`), it is treated as **field help**. 
4. If the 1st statement is a variable/expression (like `commithelp`) OR if it's a string but is *not* immediately before an assignment (e.g. it's followed by another string), then it is the **description**.

Would restricting "field help" to only be String-like statements solve this perfectly for your use case?
