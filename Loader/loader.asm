;loader引导加载程序
;主要功能：
;1.检测硬件信息
;2.处理器模式切换
;3.向内核传递数据

;================加载FAT12的文件系统结构
	org	10000h
	jmp	Label_Start
	%include	"fat12.inc"	;导入FAT文件结构
;================设置内核被加载的段地址和偏移地址	
	BaseOfKernelFile	equ	0x00
	OffsetOfKernelFile	equ	0x100000
;================设置内核程序的临时转存空间
	BaseTmpOfKernelAddr	equ	0x00
	OffsetTmpOfKernelFile	equ	0x7E00
;================设置内存结构数据的存储空间
	MemoryStructBufferAddr	equ	0x7E00
;================保护模式的基本数据结构
;本段程序创建了一个临时的GDT表。
;为了避免保护模式段结构的复杂性，此处将代码段和数据段的段基址设置在0x00000000处
;段限长为0xffffffff,即段可以索引0-4GB的内存地址空间
[SECTION gdt]
	LABEL_GDT:	dd	0,0
	LABEL_DESC_CODE32:	dd	0x0000FFFF,0x00CF9A00
	LABEL_DESC_DATA32:	dd	0x0000FFFF,0x00CF9200
	;GDT表的基地址和长度必须借助LGDT汇编指令才能加载到GDTR寄存器
	;GDTR寄存器是一个6B的结构，结构中低2B保存GDTbiao的长度，高4B保存GDT表的基地址
	;标识符GdtPtr是此结构的起始地址
	;该GDT表曾用于开启Big Real Model模式，由于其数据段被设置成平坦地址空间，故此FS段寄存器可以寻址整个4GB内存	   地址空间
	GdtLen	equ	$-LABEL_GDT
	GdtPtr	dw	GdtLen-1
		dd	LABEL_GDT
	;标识符SelectorCode32和SelectorData32是两个选择子，它们是段描述符在GDT表中的索引号
	SelectorCode32	equ	LABEL_DESC_CODE32-LABEL_GDT
	SelectorData32	equ	LABEL_DESC_DATA32-LABEL_GDT
;================IA-32e模式的临时GDT表结构数据
;IA-32e模式简化了保护模式的段结构，删减掉冗余的段基地址和段限长，使段直接覆盖整个线性地址空间
[SECTION gdt64]
	LABEL_GDT64:		dq	0x0000000000000000
	LABEL_DESC_CODE64:	dq	0x0020980000000000
	LABEL_DESC_DATA64:	dq	0x0000920000000000
	GdtLen64	equ	$ - LABEL_GDT64
	GdtPtr64	dw	GdtLen64 - 1
			dd	LABEL_GDT64
	SelectorCode64	equ	LABEL_DESC_CODE64 - LABEL_GDT64
	SelectorData64	equ	LABEL_DESC_DATA64 - LABEL_GDT64
;================定义.s16的段
	[SECTION .s16]
;================BITS伪指令通知NASM编译器生成的代码，将运行在16位宽的处理器上或者是32位宽的处理器
	[BITS	16]
;======================================================
Label_Start:
	mov	ax,	cs
	mov	ds,	ax
	mov	es,	ax
	mov	ax,	0x00
	mov	ss,	ax
	mov	sp,	0x7c00
;================display on screen : Start Loader......
	mov	ax,	1301h
	mov	bx,	000fh
	mov	dx,	0200h	
	mov	cx,	12
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	StartLoaderMessage
	int	10h
;=================open address A20
;开启1MB以上物理地址寻址功能，并开启实模式下的4GB寻址功能
;通过A20快速门（I/O端口0x92处理A20地址线）开启A20功能，即置位0x92端口的第1位
;通过LGDT指令加载保护模式数据结构信息，并置位CR0的第0位开启保护模式
;进入保护模式后，为FS段寄存器加载新的数据段值，一旦完成数据加载就从保护模式退出（通过该步骤进入BIG Real Model）
	push	ax
	in	al,	92h
	or	al,	00000010b
	out	92h,	al
	pop	ax
	;关中断
	cli
	;加载保护模式数据结构
	db	0x66
	lgdt	[GdtPtr]
	;置位CR0，开启保护模式
	mov	eax,	cr0
	or	eax,	1
	mov	cr0,	eax
	;FS  段寄存器加载新的数据段值
	mov 	ax,	SelectorData32
	mov	fs,	ax
	;从保护模式退出
	mov	eax,	cr0
	and	al,	11111110b
	mov	cr0,	eax
	;关中断
	sti
;=================reset floppy
	xor	ah,	ah
	xor	dl,	dl
	int	13h
;=================search kernel.bin
	mov	word	[SectorNo],	SectorNumOfRootDirStart
Lable_Search_In_Root_Dir_Begin:
	cmp	word	[RootDirSizeForLoop],	0
	jz	Label_No_LoaderBin
	dec	word	[RootDirSizeForLoop]	
	mov	ax,	00h
	mov	es,	ax
	mov	bx,	8000h
	mov	ax,	[SectorNo]
	mov	cl,	1
	call	Func_ReadOneSector
	mov	si,	KernelFileName
	mov	di,	8000h
	cld
	mov	dx,	10h	
Label_Search_For_LoaderBin:
	cmp	dx,	0
	jz	Label_Goto_Next_Sector_In_Root_Dir
	dec	dx
	mov	cx,	11
Label_Cmp_FileName:
	cmp	cx,	0
	jz	Label_FileName_Found
	dec	cx
	lodsb	
	cmp	al,	byte	[es:di]
	jz	Label_Go_On
	jmp	Label_Different
Label_Go_On:
	inc	di
	jmp	Label_Cmp_FileName
Label_Different:
	and	di,	0FFE0h
	add	di,	20h
	mov	si,	KernelFileName
	jmp	Label_Search_For_LoaderBin
Label_Goto_Next_Sector_In_Root_Dir:
	add	word	[SectorNo],	1
	jmp	Lable_Search_In_Root_Dir_Begin	
;===================display on screen : ERROR:No KERNEL Found
Label_No_LoaderBin:
	mov	ax,	1301h
	mov	bx,	008Ch
	mov	dx,	0300h	
	mov	cx,	21
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	NoLoaderMessage
	int	10h
	jmp	$               
;===================found kernel.bin name in root director struct
;负责将内核程序读取到临时转存空间中，随后再将器移动至1MB以上的物理内存空间
Label_FileName_Found:
	mov	ax,	RootDirSectors
	and	di,	0FFE0h
	add	di,	01Ah
	mov	cx,	word	[es:di]
	push	cx
	add	cx,	ax
	add	cx,	SectorBalance
	mov	eax,	BaseTmpOfKernelAddr	;BaseOfKernelFile
	mov	es,	eax
	mov	bx,	OffsetTmpOfKernelFile	;OffsetOfKernelFile
	mov	ax,	cx
Label_Go_On_Loading_File:
	push	ax
	push	bx
	mov	ah,	0Eh
	mov	al,	'.'
	mov	bl,	0Fh
	int	10h
	pop	bx
	pop	ax
;读取第一个扇区的数据
	mov	cl,	1
	call	Func_ReadOneSector
	pop	ax   
;==========================操作FS段寄存器，先将内核程序读取到临时转存空间
	push	cx
	push	eax
	push	fs
	push	edi
	push	ds
	push	esi
	
	mov 	cx,	200h
	mov	ax,	BaseOfKernelFile
	mov	fs,	ax
	mov	edi,	dword	[OffsetOfKernelFileCount]
	
	mov	ax,	BaseTmpOfKernelAddr
	mov	ds,	ax
	mov	esi,	OffsetTmpOfKernelFile
;==========================将内核程序移动到1MB以上的物理内存空间
;由于内核体积庞大必须逐个簇的读取和转存，因此每次转存内核程序片段时必须保存目标偏移值
Label_Mov_Kernel:
	mov	al,	byte	[ds:esi]
	mov	byte	[fs:edi],	al
	;偏移地址自增操作	
	inc	esi	
	inc	edi
	;为了避免转存环节出错，逐字节复制
	loop	Label_Mov_Kernel
	;设置段寄存器的地址
	mov	eax,	0x1000
	mov	ds,	eax
	;保存目标偏移值
	mov	dword	[OffsetOfKernelFileCount],	edi
	pop	esi
	pop	ds
	pop	edi
	pop	fs
	pop	eax
	pop	cx
;===================================================================================
	call	Func_GetFATEntry
	cmp	ax,	0FFFh
	jz	Label_File_Loaded
	push	ax
	mov	dx,	RootDirSectors
	add	ax,	dx
	add	ax,	SectorBalance

	jmp	Label_Go_On_Loading_File 
;=========================在屏幕上显示字符
;1.将GS段寄存器的基地址设置在0B800h处（显存地址），并将AH寄存器赋值为0Fh,将AL寄存器赋值为字母
;2.将AX寄存器的值填充到地址0B800h向后偏移（80*2+39）*2处
;3.从内存地址0B800开始，是一段专门用于显示字符的内存空间，每个字符占用两个字节的内存空间，其中低字节保存显示的字符，高字节保存字符的颜色属性
Label_File_Loaded:
	mov	ax,	0B800h
	mov	gs,	ax
	mov	ah,	0Fh	;黑底白字
	mov	al,	'G'
	mov	[gs:((80*0+39)*2)],	ax	;屏幕第0行，第39列
;=========================关闭软驱马达
;通过向I/O端口3F2h写入控制命令实现，此端口控制软盘驱动器的一部分硬件功能
KillMotor:
	push	dx
	mov	dx,	03F2h
	mov	al,	0
	out	dx,	al
	pop	dx
;=========================get memory address size type
;当内核程序不再借助临时转存空间后，临时转存空间将用于保存物理地址空间信息
;物理地址空间信息由一个结构体数组构成，计算机平台的地址空间划分情况都能从这个结构体数组中反映出来。
;该段程序借助BIOS中断服务程序INT 15h来获取物理地址空间信息，并将其保存在0x7E00地址处的临时转存空间，操作系统会在会在初始化内存管理单元时解析该结构体数组
	;BIOS中断服务程序INT 10h的主要功能号AH=13h可以实现字符串的显示功能
	mov	ax,	1301h
	mov	bx,	000Fh
	mov	dx,	0400h
	mov	cx,	24
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	StartGetMemStructMessage
	int	10h
	;初始化相关寄存器
	mov	ebx,	0
	mov	ax,	0x00
	mov	es,	ax
	mov	di,	MemoryStructBufferAddr
;BIOS中断的15号功能的主功能号AX=E820h用来获取系统中内存映地址描述符的，操作系统通常用来获取内存大小
;格式如下：
;	EAX = 0000E820h
;	EDX = 534D4150h ('SMAP')
;	EBX = continuation value or 00000000h to start at beginning of map
;		持续值 或者 等于00000000h,以便重map的开头开始scan
;	ECX = size of buffer for result, in bytes (should be >= 20 bytes)
;	ES:DI -> buffer for result 
Label_Get_Mem_Struct:
	mov	eax,	0x0E820
	mov	ecx,	20
	mov	edx,	0x534D4150
	int	15h
	jc	Label_Get_Mem_Fail
	add	di,	20
	;判断是否读取完成，若读取完成转入处理阶段，否则继续读取
	cmp	ebx,	0
	jne	Label_Get_Mem_Struct
	jmp	Label_Get_Mem_OK
;如果读取失败，打印错误信息
Label_Get_Mem_Fail:
	mov	ax,	1301h
	mov	bx,	008ch
	mov	dx,	0500h
	mov	cx,	23
	push	ax	
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	GetMemStructErrMessage
	int	10h
	jmp	$
;读取成功则显示成功提示
Label_Get_Mem_OK:
	mov	ax,	1301h
	mov	bx,	000Fh
	mov	dx,	0600h
	mov	cx,	29
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	GetMemStructOKMessage
	int	10h
;===========================以下代码涉及VBE的显示模式，留待以后理解（8.31）
;=======	get SVGA information

	mov	ax,	1301h
	mov	bx,	000Fh
	mov	dx,	0800h		;row 8
	mov	cx,	23
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	StartGetSVGAVBEInfoMessage
	int	10h

	mov	ax,	0x00
	mov	es,	ax
	mov	di,	0x8000
	mov	ax,	4F00h

	int	10h

	cmp	ax,	004Fh

	jz	.KO
	
;=======	Fail

	mov	ax,	1301h
	mov	bx,	008Ch
	mov	dx,	0900h		;row 9
	mov	cx,	23
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	GetSVGAVBEInfoErrMessage
	int	10h

	jmp	$

.KO:

	mov	ax,	1301h
	mov	bx,	000Fh
	mov	dx,	0A00h		;row 10
	mov	cx,	29
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	GetSVGAVBEInfoOKMessage
	int	10h

;=======	Get SVGA Mode Info

	mov	ax,	1301h
	mov	bx,	000Fh
	mov	dx,	0C00h		;row 12
	mov	cx,	24
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	StartGetSVGAModeInfoMessage
	int	10h


	mov	ax,	0x00
	mov	es,	ax
	mov	si,	0x800e

	mov	esi,	dword	[es:si]
	mov	edi,	0x8200

Label_SVGA_Mode_Info_Get:

	mov	cx,	word	[es:esi]

;=======	display SVGA mode information

	push	ax
	
	mov	ax,	00h
	mov	al,	ch
	call	Label_DispAL

	mov	ax,	00h
	mov	al,	cl	
	call	Label_DispAL
	
	pop	ax

;=======
	
	cmp	cx,	0FFFFh
	jz	Label_SVGA_Mode_Info_Finish

	mov	ax,	4F01h
	int	10h

	cmp	ax,	004Fh

	jnz	Label_SVGA_Mode_Info_FAIL	

	add	esi,	2
	add	edi,	0x100

	jmp	Label_SVGA_Mode_Info_Get
		
Label_SVGA_Mode_Info_FAIL:

	mov	ax,	1301h
	mov	bx,	008Ch
	mov	dx,	0D00h		;row 13
	mov	cx,	24
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	GetSVGAModeInfoErrMessage
	int	10h

Label_SET_SVGA_Mode_VESA_VBE_FAIL:

	jmp	$

Label_SVGA_Mode_Info_Finish:

	mov	ax,	1301h
	mov	bx,	000Fh
	mov	dx,	0E00h		;row 14
	mov	cx,	30
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	GetSVGAModeInfoOKMessage
	int	10h

;=======	set the SVGA mode(VESA VBE)

	mov	ax,	4F02h
	mov	bx,	4180h	;========================mode : 0x180 or 0x143
	int 	10h

	cmp	ax,	004Fh
	jnz	Label_SET_SVGA_Mode_VESA_VBE_FAIL
;==========init IDT GDT goto protect mode
;处理器从实模式进入保护模式的契机是，执行mov汇编指令置位CR0控制寄存器的标志位（可同时置位CR0寄存器的PG标志位，以开启分页机制）
;进入保护模式后，处理器将从0特权级（CPL=0）开始执行
;模式切换的步骤：
;	1.执行CLI汇编指令禁止可屏蔽硬件中断，对于不可屏蔽中断NMI只能借助外部电路才能禁止（模式切换必须保证在切换过程中不能产生异常和中断）
;	2.执行LGDT汇编指令将GDT的基地址和长度加载到GDTR寄存器
;	3.执行mov CR0汇编指令置位CR0控制寄存器的PE标志位。（可同时置位CR0控制寄存器的PG标志位）
;	4.一旦Mov CR0汇编指令执行结束，紧随其后必须执行一条远跳转（far JMP）或远调用（far CALL）指令，以切换到保护模式的代码去执行（这是典型的保护模式切换方法）
;	5.通过执行JMP或CALL指令，可改变处理器执行的流水线，进而使处理器加载执行保护模式的代码段。
;	6.如果开启分页机制，那么MOV CR0指令和JMP/CALL指令必须位于同一线性地址映射的页面内。（因为保护模式和分页机制使能后的物理地址，与执行JMP/CALL指令前的线性地址相同）至于JMP和CALL指令的目标地址则无需进行同一线性地址映射。
;	7.如需使用LDT，则必须借助LLDT汇编指令将GDT内的LDT段选择子加载到LDTR寄存器中
;	8.执行LTR汇编指令将一个TSS段描述符的段选择子加载到TR任务寄存器。处理器对TSS段结构无特殊要求，凡是可写的内存空间皆可。
;	9.进入保护模式之后，数据段寄存器仍旧保留着实模式的段数据，必须重新加载数据段选择子或使用JMP/CALL指令执行新任务，便可将其更新为保护模式。对于不使用数据段寄存器（DS和SS寄存器除外），可将NULL段选择子加载到其中。
;	10.执行LIDT指令，将保护模式下的IDT表的基地址和长度加载到IDTR寄存器。
;	11.执行STI指令使能可屏蔽硬件中断，并执行必要的硬件操作使能NMI不可屏蔽中断
	cli
	;0x66这个字节是LGDT和LIDT汇编指令的前缀，用于修饰当前指令的操作数宽是32位
	db	0x66
	lgdt	[GdtPtr]
	;db	0x66
	;lidt	[IDT_POINTER]
	mov	eax,	cr0
	or	eax,	1
	mov	cr0,	eax
	;远跳转指令明确指定跳转的目标代码段选择子和段内偏移地址。
	jmp 	dword	SelectorCode32:GO_TO_TMP_Protect
[SECTION .s32]
[BITS 32]
;从GO_TO_TMP_Protect地址处开始执行IA-32e模式的切换程序
GO_TO_TMP_Protect:
;==========go to tmp long mode
;初始化各个段寄存器及其栈指针，然后检测处理器是否支持IA-32e模式。如果不支持就进入待机状态，支持就开始向长模式切换
	mov	ax,	0x10
	mov	ds,	ax
	mov	es,	ax
	mov	fs,	ax
	mov	ss,	ax
	mov	esp,	7E00h
	;检测是否支持长模式
	call	support_long_mode
	test	eax,	eax
	;若不支持，就进入待机状态
	jz	no_support
;==========init temporary page table 0x90000
;将IA-32e模式的页目录首地址设置在0x90000处，并相继配置各级页表项的值（该值由页表的起始地址和页属性组成）
	mov	dword	[0x90000],	0x91007
	mov	dword	[0x90800],	0x91007		

	mov	dword	[0x91000],	0x92007

	mov	dword	[0x92000],	0x000083

	mov	dword	[0x92008],	0x200083

	mov	dword	[0x92010],	0x400083

	mov	dword	[0x92018],	0x600083

	mov	dword	[0x92020],	0x800083

	mov	dword	[0x92028],	0xa00083
;==========load GDTR
;重新加载全局描述符，并初始化大部分寄存器
;代码段寄存器cs不能采用直接赋值的方式改变，必须借助跨段跳转指令或跨段调用指令才能实现改变
	db	0x66
	lgdt	[GdtPtr64]
	mov	ax,	0x10
	mov	ds,	ax
	mov	es,	ax
	mov	fs,	ax
	mov	gs,	ax
	mov	ss,	ax
	mov	esp,	7E00h
;==========open PAE
;通过置位CR4控制寄存器的第5位（PAE功能的标志位），开启物理地址扩展功能
	mov	eax,	cr4
	bts	eax,	5
	mov	cr4,	eax
;==========load cr3
;将临时页目录的首地址设置到CR3控制寄存器中
;在向保护模式切换的过程中未开启分页机制，考虑到稍后IA-32e模式切换过程必须关闭分页机制重新构造页表结构
	mov	eax,	0x90000
	mov	cr3,	eax
;==========enable long-mode
;置位IA32_EFER寄存器的LME标志位激活IA-32e模式
;IA32_EFER寄存器位于MSR寄存器组内，它的第8位使LME标志位
;为了操作IA32_EFER寄存器，必须借助特殊汇编指令RDMSR/WRMSR
	mov	ecx,	0C0000080h
	rdmsr
	bts	eax,	8
	wrmsr
;==========open PE and paging
;使能分页机制（置位CR0控制寄存器的PG标志位）
	mov	eax,	cr0
	bts	eax,	0
	bts	eax,	31
	mov	cr0,	eax
;使用跨段跳转/调用指令将cs段寄存器的值更新位IA-32e模式的代码段描述符
	jmp	SelectorCode64:OffsetOfKernelFile
;==========test support long or not
;CPUID汇编指令的扩展功能项0x80000001的第29位只是处理器是否支持IA-32e模式
;本段程序首先检测当前处理器对CPUID汇编指令的支持情况，判断该指令的最大功能扩展号是否超过0x80000000.
;若超过，读取相应的标志位，并将读取结果送入EAX寄存器供模块调用者判断
support_long_mode:
	mov	eax,	0x80000000
	cpuid
	cmp	eax,	0x80000001
	setnb	al
	jb	support_long_mode_done
	mov	eax,	0x80000001
	cpuid
	bt	edx,	29
	setc	al
support_long_mode_done:
	movzx	eax,	al
	ret
;==========no support
no_support:
	jmp	$
;==========read one sector from floppy
;该模块负责实现软盘读取功能,但仅仅是对BIOS中断服务程序的再次封装
;BIOS中断服务程序INT 13h的主功能号AH=02h可以实现软盘扇区读取功能
;调用该函数需传入参数AX（待读取的磁盘起始扇区号）,CL(读入扇区的数量)，ES：BX目标缓冲区的起始地址
;1.保存栈帧寄存器和栈寄存器的值
;2.计算目标磁道号和目标磁道内起始扇区号
;3.执行INT 13h中断服务程序，读取数据到内存中
[SECTION .s16lib]
[BITS 16]

Func_ReadOneSector:
	push	bp
	mov	bp,	sp
	sub	esp,	2
	mov	byte	[bp-2],	cl
	push	bx
	mov	bl,	[BPB_SecPerTrk]
	div	bl
	inc	ah
	mov	cl,	ah
	mov	dh,	al
	shr	al,	1
	mov	ch,	al
	and	dh,	1
	pop	bx
	mov	dl,	[BS_DrvNum]
Label_Go_On_Reading:
	mov	ah,	2
	mov	al,	byte	[bp-2]
	int	13h
	jc	Label_Go_On_Reading
	add	esp,	2
	pop	bp
	ret
;==========get FAT Entry
;由于每个FAT表项占用12bit，因此，FAT表项的存储位置是具有奇偶性
;该模块根据当前FAT表项索引出下一个FAT表项，AH=FAT表项号
;1.保存表项号
;2.通过将FAT表扩大1.5倍，判读存储位置的奇偶性
;3.计算FAT表项的偏移扇区号和扇区内偏移位置
;4.连续读入两个扇区的数据，并根据奇偶标志处理旧项错位问题
Func_GetFATEntry:
	push	es
	push	bx
	push	ax
	mov	ax,	00
	mov	es,	ax
	pop	ax
	mov	byte	[Odd],	0
	mov	bx,	3
	mul	bx
	mov	bx,	2
	div	bx
	cmp	dx,	0
	jz	Label_Even
	mov	byte	[Odd],	1
Label_Even:
	xor	dx,	dx
	mov	bx,	[BPB_BytesPerSec]
	div	bx
	push	dx
	mov	bx,	8000h
	add	ax,	SectorNumOfFAT1Start
	mov	cl,	2
	call	Func_ReadOneSector

	pop	dx
	add	bx,	dx
	mov	ax,	[es:bx]
	cmp	byte	[Odd],	1
	jnz	Label_Even_2
	shr	ax,	4	;若是奇数项需要向右移动4位
Label_Even_2:
	and	ax,	0fffh
	pop	bx
	pop	es
	ret
;==============display num in al
;显示一些查询出的结果
Label_DispAL:
	;保存即将变更的寄存器
	push 	ecx
	push	edx
	push	edi
	;将屏幕偏移值载入到edi寄存器中，并向AH寄存器写入字体属性
	;将16进制的数值显示在屏幕上
	mov	edi,	[DisplayPosition]
	mov	ah,	0Fh
	mov	dl,	al
	shr	al,	4
	mov	ecx,	2
.begin:
	and 	al,	0Fh
	cmp	al,	9
	ja	.1
	add	al,	'0'
	jmp	.2
.1:
	sub	al,	0Ah
	add	al,	'A'
.2:
	mov	[gs:edi],	ax
	add	edi,	2
	mov	al,	dl
	loop	.begin	
	mov	[DisplayPosition],	edi
	;现场还原
	pop	edi	
	pop	edx
	pop	ecx
	;子程序返回
	ret
;==============tmp IDT
;为IDT表开辟内存空间
;在处理切换至保护模式前，引导加载程序已使用CLI指令禁止外部中断，所以在切换到保护模式的的过程中不会产生中断和异常，进而不必完整的初始化IDT，只要有相应的结构体即可
IDT:
	times	0x50	dq	0
IDT_END:

IDT_POINTER:
		dw	IDT_END-IDT-1
		dd	IDT
;=======	tmp variable

	RootDirSizeForLoop	dw	RootDirSectors
	SectorNo		dw	0
	Odd			db	0
	OffsetOfKernelFileCount	dd	OffsetOfKernelFile
	DisplayPosition		dd	0

;=======	display messages

	StartLoaderMessage:	db	"Start Loader"
	NoLoaderMessage:	db	"ERROR:No KERNEL Found"
	KernelFileName:		db	"KERNEL  BIN",0
	StartGetMemStructMessage:	db	"Start Get Memory Struct."
	GetMemStructErrMessage:	db	"Get Memory Struct ERROR"
	GetMemStructOKMessage:	db	"Get Memory Struct SUCCESSFUL!"

	StartGetSVGAVBEInfoMessage:	db	"Start Get SVGA VBE Info"
	GetSVGAVBEInfoErrMessage:	db	"Get SVGA VBE Info ERROR"
	GetSVGAVBEInfoOKMessage:	db	"Get SVGA VBE Info SUCCESSFUL!"

	StartGetSVGAModeInfoMessage:	db	"Start Get SVGA Mode Info"
	GetSVGAModeInfoErrMessage:	db	"Get SVGA Mode Info ERROR"
	GetSVGAModeInfoOKMessage:	db	"Get SVGA Mode Info SUCCESSFUL!"

