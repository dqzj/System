;为虚拟软盘创建FAT12文件系统引导扇区数据
	org 0x7c00
BaseOfStack	equ	0x7c00
;BaseOfLoader和OffsetOFLoader组合成了Loader程序的起始物理地址
;实模式下经过地址变换得到起始物理地址0x10000
BaseOfLoader	equ	0x1000
OffsetOfLoader	equ	0x00
;RootDirSectors定义了根目录占用的扇区数
RootDirSectors	equ	14
;SectorNumOfRootDirStart定义了根目录的起始扇区号
;根目录下起始扇区号=保留扇区号+FAT表扇区数*FAT表份数
SectorNumOfRootDirStart	equ	19
SectorNumOfFAT1Start	equ	1
;SectorBalance用于平衡文件或目录的起始簇号与数据区起始簇号的差值
SectorBalance	equ	17
	jmp	short Label_Start
	nop
	BS_OEMName	db	'MINEboot'
	BPB_BytesPerSec	dw	512
	BPB_SecPerClus	db	1
	BPB_RsvdSecCnt	dw	1
	BPB_NumFATs	db	2
	BPB_RootEntCnt	dw	224
	BPB_TotSec16	dw	2880
	BPB_Media	db	0xf0
	BPB_FATSz16	dw	9
	BPB_SecPerTrk	dw	18
	BPB_NumHeads	dw	2
	BPB_HiddSec	dd	0
	BPB_TotSec32	dd	0
	BS_DrvNum	db	0
	BS_Reserved1	db	0
	BS_BootSig	db	0x29
	BS_VolID	dd	0
	BS_VolLab	db	'boot loader'
	BS_FileSysType	db	'FAT12   '
;将cs寄存器的段基址设置到DS，ES，SS等寄存器中以及设置栈指针寄存器SP
Label_Start:
	mov	ax,	cs
	mov	ds,	ax
	mov	es,	ax
	mov	ss,	ax
	mov	sp,	BaseOfStack
;==========clear screen
;BIOS中断服务程序INT 10h的主功能号AH=06h可以实现按指定范围滚动窗口的功能
;当AL=00h时，执行清屏功能，其他bx，cx，dx将不起作用
	mov	ax,	0600h
	mov	bx,	0700h
	mov	cx,	0
	mov	dx,	0184fh
	int	10h
;==========set focus
;BIOS中断服务程序INT 10h的主要功能号AH=02h可以实现屏幕光标位置的设置功能
;DH和DL分别设置光标所在的行数与列数，BH设置页码
	mov	ax,	0200h
	mov	bx,	0000h
	mov	dx,	0000h
	int	10h
;==========display on screen:Start Booting.......
;BIOS中断服务程序INT 10h的主要功能号AH=13h可以实现字符串的显示功能
;AL设置写入模式，CX设置字符串长度，DH和DL分别设置光标的行列位置，ES：BP要显示字符串的内存地址，BH设置页码，BL设置字符属性
	mov	ax,	1301h
	mov	bx,	000fh
	mov	dx,	0000h
	mov	cx,	10
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	StartBootMessage
	int	10h
;==========reset floopy
;实现软盘驱动器复位功能，相当于重新初始化一次软盘驱动器，从而将软盘驱动器的磁头移动到默认位置
;BIOS中断服务程序INT 13h的主功能号AH=00h可以实现重置磁盘驱动器的功能
;DL代表驱动器号，00h-7Fh:软盘，80h-0FFh：硬盘
	xor	ah,	ah
	xor	dl,	dl
	int	13h
;==========search loader.bin
;从根目录中搜索出引导加载程序（文件名loader.bin）
;1.保存根目录的起始扇区号，并确定需要搜索的扇区数
;2.从根目录中读入一个扇区的数据到缓冲区
;3.遍历缓冲区中的目录项，寻找与目标文件相匹配的的目录项
;4.若找到则跳转Label_FileName_Found处执行；否则在屏幕打印提示信息
	mov	word	[SectorNo],	SectorNumOfRootDirStart
Label_Search_In_Root_Dir_Begin:
	cmp	word	[RootDirSizeForLoop],	0
	jz	Label_No_LoaderBin	;jz=jump if zero
	dec	word	[RootDirSizeForLoop]
;指定数据缓冲区ES：BX
	mov	ax,	00h
	mov	es,	ax
	mov	bx,	8000h
;读入第一个扇区至缓冲区
	mov	ax,	[SectorNo]
	mov	cl,	1
	call	Func_ReadOneSector
	mov	si,	LoaderFileName
	mov	di,	8000h
	cld
	mov	dx,	10h	;记录未搜索目录项项数，初始512/32=16=0x10
Label_Search_For_LoaderBin:
	cmp	dx,	0
	jz	Label_Goto_Next_Sector_In_Root_Dir
	dec	dx
	mov	cx,	11	;cx是目录项的大小，表明需要比较的字节数
Label_Cmp_FileName:
	cmp	cx,	0
	jz	Label_FileName_Found
	dec	cx
	lodsb
	cmp	al,	byte	[es:di]	;al和数据缓冲区内的字符逐一比较
	jz	Label_Go_On
	jmp	Label_Different
Label_Go_On:
	inc	di
	jmp	Label_Cmp_FileName
Label_Different:	;直接跳到下一个目录项继续进行比较
	and	di,	0ffe0h
	add	di,	20h
	mov	si,	LoaderFileName
	jmp	Label_Search_For_LoaderBin
Label_Goto_Next_Sector_In_Root_Dir:
	add	word	[SectorNo],	1
	jmp	Label_Search_In_Root_Dir_Begin
;==========display on screen :ERROR:No LOADER Found
Label_No_LoaderBin:
	mov	ax,	1301h
	mov	bx,	008ch
	mov	dx,	0100h
	mov	cx,	21
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	NoLoaderMessage
	int	10h
	jmp	$	;	该指令表示程序在此死循环
;==========found loader.bin name in root director struct
;1.取得目录项DIR_FstClus字段的数值
;2.配置es和bx寄存器指定loader.bin在内存中的位置
;3.根据loader.bin程序的起始簇号计算其对应的扇区号将loader.bin文件的数据全部读取到内存
;4.跳转并准备执行loader.bin程序
Label_FileName_Found:
	mov	ax,	RootDirSectors
	and	di,	0ffe0h
	add	di,	01ah
	mov	cx,	word	[es:di]
	push	cx
	add	cx,	ax
	add	cx,	SectorBalance
	mov	ax,	BaseOfLoader
	mov	es,	ax
	mov	bx,	OffsetOfLoader
	mov	ax,	cx
Label_Go_On_Loading_File:
;每装载一个扇区，屏幕上打印一个.
;BIOS中断服务程序INT 10h的主功能号AH=0eh可以实现在屏幕上显示一个字符的功能
	push	ax
	push	bx
	mov	ah,	0eh
	mov	al,	'.'
	mov	bl,	0fh
	int	10h
	pop	bx
	pop	ax
;循环读入Loader.bin的数据，并通过Func_GetFATEntry取得下一个FAT表项	
	mov	cl,	1
	call	Func_ReadOneSector
	pop	ax
	call	Func_GetFATEntry
	cmp	ax,	0fffh
	jz	Label_File_Loaded
	push	ax
	mov	dx,	RootDirSectors	
	add	ax,	dx
	add	ax,	SectorBalance
	add	bx,	[BPB_BytesPerSec]
	jmp	Label_Go_On_Loading_File
Label_File_Loaded:
	jmp	BaseOfLoader:OffsetOfLoader
;==========read one sector from floppy
;该模块负责实现软盘读取功能,但仅仅是对BIOS中断服务程序的再次封装
;BIOS中断服务程序INT 13h的主功能号AH=02h可以实现软盘扇区读取功能
;调用该函数需传入参数AX（待读取的磁盘起始扇区号）,CL(读入扇区的数量)，ES：BX目标缓冲区的起始地址
;1.保存栈帧寄存器和栈寄存器的值
;2.计算目标磁道号和目标磁道内起始扇区号
;3.执行INT 13h中断服务程序，读取数据到内存中
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
;========tmp variable
RootDirSizeForLoop	dw	RootDirSectors
SectorNo		dw	0
Odd			db	0
;========display messages
StartBootMessage:	db	"Start Boot"
NoLoaderMessage:	db	"ERROR:No LOADER Found"
LoaderFileName:		db	"LOADER  BIN",0
;========fill zero until whole sector
	times	510 - ($ - $$)	db	0
	dw	0xaa55
