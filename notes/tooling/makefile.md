# A Brief Introduction to Makefile

## Introduction
Makefile is a script file that is written to automate compilation and linking of program files, and also to track prerequisites. It works by comparing prerequisites and target with respect to the timestamps in order to run or avoid running the commands listed in the target.

## Structure of Makefile Script
The structure of a Makefile script is as below:

```makefile
target: prerequisites
    command
```

where:
- `target` is either a filename or a general target name
- `prerequisites` are either filename/s or target name/s
- `command` is the combination of compiler arguments and flags. It starts after a tab character. It is also called a *recipe*.

## Working
Makefile works by comparing the timestamp of the target with its prerequisites. For example, let's say we have the following folder structure:

```
~/
 build/
      lib.o
      test.o
      out
 tests/
      test.c   
 lib.c
 lib.h
 Makefile 
```

A Makefile script to compile and build the above program files could be as follows:

```makefile
build/lib.o: lib.c lib.h
    gcc -Wall -c lib.c -o build/lib.o
build/test.o: test.c
    gcc -Wall -c test.c -o build/test.o
build/out: build/test.o build/lib.o
    gcc -Wall build/lib.o build/test.o -o build/out
run: build/out
    ./build/out
```

**Example 1**

Let's assume that we have just written to the `lib.c` and `test.c` files and we run the command `make build/out`.

This command will run the target `build/out`. At first, make will access the prerequisites of `build/out` and get to know that they are targets with their own rules. So it will go to the first prerequisite target i.e. `build/test.o`. It will check the prerequisites of `build/test.o` which is `test.c` and compare the timestamps of `test.c` against `build/test.o`. Since there are recent changes in `test.c` resulting in a timestamp difference, make will run the commands of the `build/test.o` target. Then again it will move to another prerequisite of `build/out` which is `build/lib.o` and compare timestamps of `build/lib.o` and `lib.c`, which will be different. Make will also run the commands of `build/lib.o`.

**Example 2**

Let's assume that this time we are running the command `make run`.

At first make will go to the target `run` then check its prerequisites. The prerequisite `build/out` is also a target itself. So make will go to `build/out` target then analyze the prerequisites and compare the timestamps to run the commands. Let's say this time there are no new changes made to the files. Make will go to the targets of each prerequisite of `build/out` like in example 1 and check if the timestamps differ. Since there are no changes made, timestamps remain the same, thus make will not run anything, then return to the `run` target.

In the `run` target, `run` is a target name but it doesn't exist as a file in the project. Make treats the target `run` as a phony target. Make treats the target name as a filename unless explicitly mentioned as a phony target. If the target filename doesn't exist, it is always considered out-of-date. That's why the command of the `run` target gets executed all the time.

## Phony Target
Make treats target names as filenames by default if not mentioned explicitly. If we want a target not to be treated as a filename then we explicitly mention that target as `.PHONY`.

In example 2, the `run` target doesn't exist as a file in the project. Make treats it as a file target, sees that `run` doesn't exist, considers it out-of-date, and therefore always runs the command (`./build/out`). This is implicit behavior for non-existent file targets.

If a target exists as a filename but we want make to execute the commands every time even though the prerequisite hasn't been modified, then we mention that target as `.PHONY`.

```makefile
.PHONY: clean
clean: 
    rm -rf build
```

Even though there is a filename named `clean` in a project, make treats it like the filename doesn't exist, making sure the `clean` target always gets to run.

## Prerequisite Execution Order

```makefile
main.o: test.c bump.o
    commands for main.o

bump.o: extra.c
    commands for bump.o
```

Make processes prerequisites recursively and (in serial mode) usually left-to-right unless concurrent mode is enabled using available flags.

For the `main.o` target:
- First checks `test.c` which is a plain source file and doesn't exist as a target. Make compares its timestamp against `main.o`.
- Then reaches `bump.o` and notices it has its own rule. Make recursively resolves `bump.o` first — goes to the `bump.o` target, checks the prerequisite `extra.c` timestamp vs `bump.o`, and runs the commands of `bump.o` if needed.
- After `bump.o` is resolved, compares its timestamp against `main.o`.
- Finally, if either `test.c` or `bump.o` is newer/missing, runs the recipe of `main.o`.

This behaviour of running the prerequisite first if it exists as a target is recursive.

## Variables
The above Makefile script can be rewritten to use variables.

Automatic variable meanings:
- `$@` → target name
- `$^` → all prerequisites
- `$<` → first prerequisite

```makefile
CC = gcc
CC_FLAGS = -Wall -c

build/lib.o: lib.c lib.h
    ${CC} ${CC_FLAGS} $< -o $@
build/test.o: test.c
    ${CC} ${CC_FLAGS} $^ -o $@
build/out: build/test.o build/lib.o
    ${CC} -Wall $^ -o $@
run: build/out
    ./build/out
```
