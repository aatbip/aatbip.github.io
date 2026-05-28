---
title: Bitmasking technique
---

# Bitmasking technique: Get base address of aligned memory region

In low level programming, there are a lot of instances where we make use of bit masking. 

In my project objcache, I used a bit masking technique which took benefit from the operating system’s address space structure. I want to share my understanding 
and request for your feedback.

In the program page sized buffers were allocated. The virtual address of a random offset of a page was available and then I needed to find the base address 
of that page where a struct was stored. The `GET_SLABBASE` parameterized macro at line no 11 in the image attached does the trick. Below I will try to explain 
why does it work and how we can take benefit from how the virtual address space is structured. 

### Note
This technique only works if the allocated memory is page aligned. `mmap` always returns a page aligned pointer but `malloc` may not. There is 
another glibc function `posix_memalign` which I used in my project to allocate memory with the required alignment. 

The virtual address space provided by the kernel for each process consists of 2 parts which are virtual page number (VPN) and the offset. Assume that we 
have a 4 bit address space, then the first 2 bits represents the VPN and the latter 2 bits are offset. This structure helps mapping the VPN to the actual 
physical page frame number (PFN) using the page table entry (PTE).

So with our 4 bits address space assumption, the total amount of addressable memory is 2^4 = 16 bytes. With first 2 bits as VPN, we can have 2^2 = 4 pages.

```markdown

0  | 0000 --- page 1

1  | 0001

2  | 0010 

3  | 0011 ---

4  | 0100 --- page 2

5  | 0101

6  | 0110 

7  | 0111 ---

8  | 1000 --- page 3

9  | 1001

10 | 1010 

11 | 1011 ---

12 | 1100 --- page 4

13 | 1101

14 | 1110 

15 | 1111 ---
```
Fig: 4 bit address space (16 bytes)

### Problem
Find the base address of the page given the address of an offset. For ex: If the address `1010` is available from page 3, find the base address 
of page 3 which is `1000`.

### Solution
Since we know the fact that the first 2 bits of the address space represents the VPN, we need to clear the last 2 bits to get the base address. 
The offset mask to do this is `page_size – 1` because page_size – 1 has all offset bits set, bitwise NOT operator flips the bits of the offset mask, 
then bitwise AND operator with the memory address clears the offset bits keeping only the VPN bits producing the base address.

```markdown
Base address = offset & ~(page_size – 1)

= 1010 & ~(0011), because page size is 4 bytes.

= 1000, which is the base address of page 3.
```
