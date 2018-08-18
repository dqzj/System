#include <stdio.h>
void example()
{
	printf("%s\n",__FUNCTION__);
}

int main()
{
	example();
	return 0;
}
