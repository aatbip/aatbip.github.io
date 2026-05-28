---
title: File IO Race Condition Bugs
---

# Exploring common race conditions while using file I/O syscalls in multithreaded programs</a>

### Introduction
In this note, I discuss about race conditions caused by using file I/O syscalls in the multithreaded or multiprocess programs and ways to eliminate such
race condition bugs.

### Program 1

```C

/*This program contains a race condition bug. When two processes 
*run this program simultaneously then even though only
*one process actually creates the file but the other process 
*also thinks that it has opened the file. We can instead
*use O_EXCL that ensures atomicity for checking the file existence 
*and creating only if it doesn't exist.*/

#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
  int fd = open(argv[1], O_RDWR);
  if (fd != -1) {
    printf("[PID: %d] File \"%s\" already exists.\n", getpid(), argv[1]);
  } else {
    if (argc > 2) {
      printf("[PID: %d] Sleeping...\n", getpid());
      sleep(10);
    }
    int fd = open(argv[1], O_CREAT | O_RDWR, 0700);
    if (fd == -1) {
      perror("open");
    }
    printf("[PID: %d] Created the file \"%s\"\n", getpid(), argv[1]);
  }
  close(fd);
  return 0;
}
```

If we want to open a file only if it doesn’t exist yet (exclusive open) then one way to do that is by manually calling the open syscall and check for its error to know if file exist or not, if the file doesn’t exist then use open syscall again to create the file. However, this program contains a race condition bug if it is run by multiple processes/threads. If process A and process B are running this program then both the processes will end up assuming that they have created the file even though only one of them actually created the file.

The syscall provides O_EXCL flag which can be used along with O_CREAT so that kernel ensures atomicity through the use of kernel space locking mechanism more precisely using the read-write semaphore. This makes it possible to check if file exists or not and then create the file without another process contending on this.

### Program 2

```C

/*This program demonstrate the atomicity kernel guarantees when 
*used O_APPEND flag. Kernel performs the seek and write
*operation within a lock that will prevent race condition that 
*would be seen without using O_APPEND and using lseek
*manually which if ran by multiprocess/multithread would overwrite 
*the written data.*/

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
  int fd;
  if ((fd = open("test", O_CREAT | O_RDWR | O_APPEND, 0700)) == -1) {
    perror("open");
    exit(EXIT_FAILURE);
  }
  // if (lseek(fd, 0, SEEK_END) == -1) {
  //   perror(("lseek"));
  //   exit(EXIT_FAILURE);
  // }
  if (argc > 2) {
    printf("sleeping...\n");
    sleep(20);
  }
  if (write(fd, argv[1], strlen(argv[1])) < strlen(argv[1])) {
    char *err = "err: partial or no write";
    write(STDERR_FILENO, err, strlen(err));
    exit(EXIT_FAILURE);
  }
  close(fd);
  exit(EXIT_SUCCESS);
}
```
In this program, a file is opened using the open syscall and then lseek syscall is used to manually move the seek beyond the EOF in order to append write to the file. If two processes are running this then the process that sleeps will end up overwriting the data written by another process. This happens because process A will run until lseek call and then sleeps, then process B will run and write the file. After that process A wakes up and writes the file from the previously updated seek position which ends up overwriting the data.

Again, we can make use of the O_APPEND flag so that kernel ensures that the seek and write operations happen atomically.

### User space synchronization?
My thought was can we use the same programs but fix the race condition bug through user space synchronization? In a multithreaded environment, using mutex lock across the critical section can help fix it but then in a multiprocess environment we cank’t share a lock across multiple processes since multiple processes don’t share the same address space. In such case I think creating a shared memory region for the processes or just using semaphore can work. Please share your opinions on this.
