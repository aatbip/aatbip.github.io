---
title: Signals
---

# Analyzing signal delivery in relation to signal dispatch and handler function execution time 

Table of Contents

1. [Introduction](#introduction)
2. [Parallel signal dispatch using multiple threads](#parallel-signal-dispatch-using-multiple-threads)
3. [Signal delivery while handler function is still running and `SA_NODEFER` flag](#signal-delivery-while-handler-function-is-still-running-and-sa_nodefer-flag)
4. [Conclusion](#conclusion)

## Introduction
The programs below analyzes singal delivery behaviour with respect to the signal dispatch methods and handler function execution time.
Multiple scenarios are analyzed that are as follows: 

- signal of same type is dispatched parallelly using multiple threads
    - a long running handler function was registered 
    - a short running handler function was registered 
- signal of same type is dispatched while handler function hasn't returned yet
- effect of SA_NODEFER flag on signal delivery

Now we will analyze the above conditions.

## Parallel signal dispatch using multiple threads

In the program below, parent process creates four threads which run the `routine` in parallel. `routine` sends the signal typed in shell using `kill` system call
to the child process. The child process has registered signal handler `sig_handle` function which has a long running job described by the for loop iterating 
for 999999999 times.

```C

#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

typedef struct sig_handler_param {
  pid_t pid;
  int sig;
} sig_handler_param_t;

#define THREAD_CNT 4

static volatile sig_atomic_t gotSigTerm = 0;

void print_sig(sigset_t *set) {
  for (int i = 1; i < NSIG; i++) {
    if (sigismember(set, i)) {
      write(STDOUT_FILENO, "pending\n", 8);
    }
  }
}

void *routine(void *p) {
  sig_handler_param_t *param = (sig_handler_param_t *)p;
  if (kill(param->pid, param->sig) == -1) {
    perror("kill");
  }
  return NULL;
}

void sig_handle(int sig) {
  if (sig == SIGTERM) {
    sigset_t pending;
    for (int i = 0; i < 999999999; i++)
      ;
    if (sigpending(&pending) == -1) {
      perror("sigpending");
      exit(EXIT_FAILURE);
    }
    print_sig(&pending);
    write(STDOUT_FILENO, "Received\n", 9);
  }
  if (sig == SIGQUIT || sig == SIGCHLD) {
    exit(EXIT_SUCCESS);
  }
}

int main(int argc, char *argv[]) {
  pid_t pid;
  switch ((pid = fork())) {
  case -1:
    perror("fork");
    exit(EXIT_FAILURE);

  // child process
  case 0:
    printf("\nChild pid: %d\n", getpid());

    if (signal(SIGTERM, sig_handle) == SIG_ERR || signal(SIGQUIT, sig_handle) == SIG_ERR) {
      perror("signal disposition");
      exit(EXIT_FAILURE);
    }

    /*Run child process forever until SIGTERM is received.*/
    for (;;)
      ;

  // parent process
  default:
    printf("Parent pid: %d\n", getpid());
    /*Register SIGCHLD in parent to terminate parent when child exits*/
    if (signal(SIGCHLD, sig_handle) == SIG_ERR) {
      perror("signal disposition");
      exit(EXIT_FAILURE);
    }

    pthread_t *th = malloc(sizeof(pthread_t) * THREAD_CNT);

    sig_handler_param_t *param = malloc(sizeof(sig_handler_param_t));
    for (;;) {
      int sig;
      printf("Enter signal identifier: ");
      scanf("%d", &sig);
      param->pid = pid;
      param->sig = sig;
      for (int i = 0; i < THREAD_CNT; i++) {
        if (pthread_create(&th[i], NULL, routine, param) != 0) {
          perror("pthread_create");
        }
        pthread_detach(th[i]);
      }
    }
  }
}

```
The syscall `kill` dispatched in parallel by the parent process will get serialized while updating the kernel data structure for handling signal. This happens because
kernel acquires the `siglock` spinlock to avoid contention resulting in only one signal out of four being able to deliver at a time. The output of the above program 
if `SIGTERM` is sent from the parent process by typing number 15 in the shell is as follows:

```shell

Parent pid: 63923
Enter signal identifier: 
Child pid: 63924
15
Enter signal identifier: pending
Received
Received
```

Since the signal delivery will be serialized, child process receives the first signal which will invoke the `sig_handle` handler function. The handler 
function is long running which takes a certain amount of CPU time to return after finishing the execution. While the handler function is still running, 
second signal is also received. This signal will be added to the process signal mask (blocked) which sets the pending signal for `SIGTERM` in this process. 
Remaining two signals will also get received but since this signal is already masked and standard UNIX signals are not queued, they can make no further changes.

Now the `sig_handle` handler function invoked by the first delivered signal will print the string literal "pending" because the second signal has set the pending
bit. Then it prints "Received" before returning. Next, the pending signal will invoke the signal handler function. This time no other signal is pending so it 
prints "Received" before finally returning.

If the `sig_handle` function is made short running then the output is completely different and unreliable. The long running for loop is removed from the `sig_handle`
handler function to make it short running. 

```C 

void sig_handle(int sig) {
  if (sig == SIGTERM) {
    sigset_t pending;
    if (sigpending(&pending) == -1) {
      perror("sigpending");
      exit(EXIT_FAILURE);
    }
    print_sig(&pending);
    write(STDOUT_FILENO, "Received\n", 9);
  }
  if (sig == SIGQUIT || sig == SIGCHLD) {
    exit(EXIT_SUCCESS);
  }
}

```

The output of this changes is as follows when sending the `SIGTERM` signal multiple times:

```shell

Parent pid: 64634
Enter signal identifier: 
Child pid: 64635
15
pending
Received
Received
Enter signal identifier: Received
Received
15
Received
Enter signal identifier: Received
Received
Received
15
Received
Enter signal identifier: pending
Received
Received
Received
15
pending
Received
pending
Received
Enter signal identifier: Received
Received
15
pending
Received
Received
Enter signal identifier: Received

```

By looking at the output the following conclusion can be made:

- When the signal handler is short running, all four concurrently dispatched signals are delivered in some runs. This is because the handler function completes fast 
enough between the serialized `kill` calls that the pending bit gets cleared and reset multiple times allowing all 4 deliveries.
- The position of "pending" string literal in the output varies across runs and in some run "pending" is not printed at all which shows that scheduling race between
signal delivery and handler function execution.
- Signal delivery count and ordering is non-deterministic across runs. This demonstrates that signal delivery is tied to kernel scheduling decisions which are 
not under the control of userspace programs.

## Signal delivery while handler function is still running and `SA_NODEFER` flag

In this section the behaviour of signal delivery is analyzed while handler function has not returned yet and the difference `SA_NODEFER` flag makes to 
the blocking signal behaviour. Consider the program below: 

```C

void handler(int sig) {
  struct timeval tv;
  struct timezone tz;
  int i = gettimeofday(&tv, &tz);
  printf("fired\n");
  sleep(5);
  printf("time %ld\n", tv.tv_sec);
}

int main(void) {
  printf("pid: %d\n", getpid());
  struct sigaction act;
  act.sa_handler = handler;
  if (sigaction(SIGTERM, &act, NULL) == -1) {
    perror("sigaction");
  }
  for (;;)
    pause();
  exit(EXIT_SUCCESS);
}

```
When a `SIGTERM` signal is dispatched the `handler` function is invoked then it sleeps for 5 seconds. If another signal is dispatched before `handler` function 
returns then that signal will be added to the process signal mask setting the pending signal bit. Now, how much ever more signal is dispatched, no changes will 
occur and since the standard UNIX signals are not queued multiple signals will not be delivered. In total, the first and the second signals were only delivered. 
The output of running the above program and sending the `SIGTERM` signal using the `kill` program is as follows:

Signals were sent for 6 times.

```shell

kill -TERM 67082
kill -TERM 67082
kill -TERM 67082
kill -TERM 67082
kill -TERM 67082
kill -TERM 67082

```

Signals were delivered twice.

```shell

pid: 67082
fired
time 1779989567
fired
time 1779989572

```

If the pending signal is set then kernel makes sure that signal is delivered.

Now the same program is analyzed by adding the `SA_NODEFER` flag.

```C

act.sa_flags = SA_NODEFER;

```

Now if multiple signals are sent while handler function is still executing then the signals are not automatically blocked and added to the signal mask. Instead,
the signals are delivered and the handler function is resolved recursively. The output below shows the effect of the flag:

Signals were sent for 5 times.

```shell

kill -TERM 67082
kill -TERM 67082
kill -TERM 67082
kill -TERM 67082
kill -TERM 67082
kill -TERM 67082

```
`gettimeofday` records the timestamp and "fired" gets printed. Then the handler function goes to sleep for 5 seconds. At this time, another signal is 
delivered which invokes the handler function again. The same process repeats until the signal is dispatched and no signal set with `SA_NODEFER` flag gets blocked.
The timestamp recorded proves that handler gets executed in recursive manner.

```shell

pid: 67960
fired
fired
fired
fired
fired
time 1779990293
time 1779990292
time 1779990292
time 1779990291
time 1779990290

```

## Conclusion

This article discuss about various signal dispatch and delivery behaviours in the UNIX based system.
