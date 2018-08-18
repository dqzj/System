#include<stdio.h>

int main()
{
	asm("movl $1,%eax\n\t"
	"movl $0,%ebx\n\t"
	"int $0x80");

	printf("hello world");
	return 0;
}
