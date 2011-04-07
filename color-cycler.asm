.macro  lwi	reg, value
lis	\reg, \value@h
ori	\reg, \reg, \value@l
.endm

/*
int --> float conversion using red zone
freg2 holds the constant 0x4330000080000000
*/

.macro fcfid freg1,freg2,reg1

stfd \freg2,-8(r1)
xoris \reg1,\reg1,0x8000
stw \reg1,-4(r1)
lfd \freg1,-8(r1)
fsub \freg1,\freg1,\freg2

.endm


/*
PUSH and POP
*/

.macro  stmfd from, to, offset,reg
  stfd   \from,\offset(\reg) 
  .if     \to-\from
  stmfd    "(\from+1)",\to, \offset+8,\reg
  .endif
.endm

.macro  lmfd from, to, offset,reg
  lfd   \from,\offset(\reg) 
  .if     \to-\from
  lmfd    "(\from+1)",\to, \offset+8,\reg
  .endif
.endm


/*
Variables for stackframe
*/

.set numGPRs,(31-12+1)
.set numFPRs,(_saveFPRs_end - _saveFPRs_start)/4
.set spaceToSave,((4 + ((4*numGPRs + 7)& ~7) + 8*numFPRs ) +7) & ~7
.set offsetforFPR,8 + ((4*numGPRs + 7) & ~7)


# FPRs
.set PARAM_RATE,4
.set maxcolor,5
.set mincolor,6

.set H,7
.set S,8
.set L,9

.set RED,10
.set GREEN,11
.set BLUE,12

.set tmp1,13
.set tmp2,14

.set temp1,15
.set temp2,16
.set temp3,17

.set color,18

.set CONST_0.0,		19
.set CONST_0.5,		20
.set CONST_1.0,		21
.set CONST_2.0,		22
.set CONST_one_3rd,	23
.set CONST_two_3rds,	24
.set CONST_3.0,		25
.set CONST_4.0,		26
.set CONST_6.0,		27
.set CONST_60.0,	28
.set CONST_255.0,	29
.set CONST_360.0,	30
.set CONST_MAGIC,	31


# GPRs

.set anchor,12

.set red,14
.set green,15
.set blue,16

.set maxcolor_index,17
.set mincolor_index,18

.set datap,19
.set savedLR,20

#indexes
.set color_index_RED,0
.set color_index_GREEN,1
.set color_index_BLUE,2


/*-------------------------------------------------------------------------------*/

_stackframe:
stwu r1,-spaceToSave(r1)
stmw r12,8(r1)

_saveFPRs_start:
stmfd 4,31,offsetforFPR,1
_saveFPRs_end:

mflr	savedLR


/*
Set a pointer to the RGB data
Edit if needed
*/
addi	datap,r27,1392



bl	_const_data_end

_const_data:
.float	0.0
.float	0.5
.float	1.0
.float	2.0
.float	3.0
.float	0.33333333
.float	0.66666666
.float	4.0
.float	6.0
.float	60.0
.float	255.0
.float	360.0
.double	4503601774854144
/*
Color changing rate
Edit if needed
*/
.float	0.125
_const_data_end:

mflr	anchor

lfs	CONST_0.0,0(anchor)
lfs	CONST_0.5,4(anchor)
lfs	CONST_1.0,8(anchor)
lfs	CONST_2.0,12(anchor)
lfs	CONST_3.0,16(anchor)
lfs	CONST_one_3rd,20(anchor)
lfs	CONST_two_3rds,24(anchor)
lfs	CONST_4.0,28(anchor)
lfs	CONST_6.0,32(anchor)
lfs	CONST_60.0,36(anchor)
lfs	CONST_255.0,40(anchor)
lfs	CONST_360.0,44(anchor)
lfd	CONST_MAGIC,48(anchor)
lfs	PARAM_RATE,56(anchor)





# Convert the RBG values to the range 0-1

lbz	red,0(datap)
fcfid	RED,CONST_MAGIC,red
fdiv	RED,RED,CONST_255.0

lbz	green,1(datap)
fcfid	GREEN,CONST_MAGIC,green
fdiv	GREEN,GREEN,CONST_255.0

lbz	blue,2(datap)
fcfid	BLUE,CONST_MAGIC,blue
fdiv	BLUE,BLUE,CONST_255.0


/*-------------------------------------------------------------------------------*/

#RGB - HSL


/*
Find min and max values of R, B, G
*/


fmr	maxcolor,RED
fmr	mincolor,RED
li	maxcolor_index,color_index_RED
li	mincolor_index,color_index_RED

fcmpo	cr0,maxcolor,GREEN
bgt-	0f
fmr	maxcolor,GREEN
li	maxcolor_index,color_index_GREEN
0:

fcmpo	cr0,maxcolor,BLUE
bgt-	0f
fmr	maxcolor,BLUE
li	maxcolor_index,color_index_BLUE
0:

fcmpo	cr0,mincolor,GREEN
blt-	0f
fmr	mincolor,GREEN
li	mincolor_index,color_index_GREEN
0:

fcmpo	cr0,mincolor,BLUE
blt-	0f
fmr	mincolor,BLUE
li	mincolor_index,color_index_BLUE
0:


/*
L = (maxcolor + mincolor)/2 
tmp1 = (maxcolor + mincolor)
*/

fadd	tmp1,maxcolor,mincolor
fdiv	L,tmp1,CONST_2.0



/*
If the max and min colors are the same (ie the color is some kind of grey), S is defined to be 0, and H is undefined but in programs usually written as 0
*/


cmpw	maxcolor_index,mincolor_index
bne-	0f
fmr	S,CONST_0.0
fmr	H,CONST_0.0
b	_HSL2RGB
0:


/*
Otherwise, test L. 
If L < 0.5, S=(maxcolor-mincolor)/(maxcolor+mincolor)
If L >=0.5, S=(maxcolor-mincolor)/(2.0-maxcolor-mincolor)

tmp1 = (maxcolor - mincolor)
tmp2 = (maxcolor + mincolor) or tmp2 = (2.0 - (maxcolor + mincolor))
*/

fsub	tmp1,maxcolor,mincolor
fadd	tmp2,maxcolor,mincolor

fcmpo	cr0,L,CONST_0.5
blt-	0f
fsub	tmp2,CONST_2.0,tmp2
0:
fdiv	S,tmp1,tmp2



/*
If R=maxcolor, H = (G-B)/(maxcolor-mincolor)
If G=maxcolor, H = 2.0 + (B-R)/(maxcolor-mincolor)
If B=maxcolor, H = 4.0 + (R-G)/(maxcolor-mincolor)

tmp1 = (maxcolor-mincolor)
tmp2 = (X-Y) or (X-Y)/(maxcolor-mincolor)
*/

cmpwi	maxcolor_index,color_index_RED
bne-	0f
fsub	tmp2,GREEN,BLUE
fdiv	H,tmp2,tmp1
b	1f
0:

cmpwi	maxcolor_index,color_index_GREEN
bne-	0f
fsub	tmp2,BLUE,RED
fdiv	tmp2,tmp2,tmp1
fadd	H,CONST_2.0,tmp2
b	1f
0:

_maxcolor_is_BLUE:
fsub	tmp2,RED,GREEN
fdiv	tmp2,tmp2,tmp1
fadd	H,CONST_4.0,tmp2

1:


/*
To use the scaling shown in the video color page, convert L and S back to percentages, and H into an angle in degrees (ie scale it from 0-360). From the computation in step 6, H will range from 0-6. RGB space is a cube, and HSL space is a double hexacone, where L is the principal diagonal of the RGB cube. Thus corners of the RGB cube; red, yellow, green, cyan, blue, and magenta, become the vertices of the HSL hexagon. Then the value 0-6 for H tells you which section of the hexgon you are in. H is most commonly given as in degrees, so to convert
H = H*60.0
*/

fmul	H,H,CONST_60.0
fcmpo	cr0,H,CONST_0.0
bge-	0f
fadd	H,H,CONST_360.0
0:


_update_hue:

fadd	H,H,PARAM_RATE
fcmpo	cr0,H,CONST_360.0
ble-	0f
fmr	H,CONST_0.0
0:

/*---HSL - RGB---*/

_HSL2RGB:

/*
If S=0, define R, G, and B all to L
*/


fcmpo	cr0,S,CONST_0.0
bne-	0f

fmr	RED,L
fmul	RED,RED,CONST_255.0
fctiw	RED,RED
stfd	RED,-8(r1)
lwz	red,-4(r1)
stb	red,0(datap)
stb	red,1(datap)
stb	red,2(datap)
b	_return
0:


/*
Otherwise, test L.
If L < 0.5, temp2=L*(1.0+S)
If L >= 0.5, temp2=L+S - L*S

tmp1 = (1.0+S)
tmp1 = (L+S)
tmp2 = (L*S)
*/

fcmpo	cr0,L,CONST_0.5
bge-	0f
fadd	tmp1,S,CONST_1.0
fmul	temp2,L,tmp1
b	1f
0:

fadd	tmp1,L,S
fmul	tmp2,L,S
fsub	temp2,tmp1,tmp2

1:


/*
temp1 = 2.0*L - temp2
*/

fmul	tmp1,CONST_2.0,L
fsub	temp1,tmp1,temp2

/*
Convert H to the range 0-1
For each of R, G, B, compute another temporary value, temp3, as follows:

for R, temp3=H+1.0/3.0
for G, temp3=H
for B, temp3=H-1.0/3.0
*/

fdiv	H,H,CONST_360.0


fadd	temp3,H,CONST_one_3rd
bl	_calculate_color
fmul	RED,color,CONST_255.0
fctiw	RED,RED
stfd	RED,-8(r1)
lwz	red,-4(r1)
stb	red,0(datap)

fmr	temp3,H
bl	_calculate_color
fmul	GREEN,color,CONST_255.0
fctiw	GREEN,GREEN
stfd	GREEN,-8(r1)
lwz	green,-4(r1)
stb	green,1(datap)

fsub	temp3,H,CONST_one_3rd
bl	_calculate_color
fmul	BLUE,color,CONST_255.0
fctiw	BLUE,BLUE
stfd	BLUE,-8(r1)
lwz	blue,-4(r1)
stb	blue,2(datap)


b	_return



/*-----------------------------------------------------------------------------------------------------------*/

_calculate_color:


/*
if temp3 < 0, temp3 = temp3 + 1.0
if temp3 > 1, temp3 = temp3 - 1.0
*/


fcmpo	cr0,temp3,CONST_1.0
ble-	0f
fsub	temp3,temp3,CONST_1.0

0:


fcmpo	cr0,temp3,CONST_0.0
bge-	0f
fadd	temp3,temp3,CONST_1.0

0:




/*
For each of R, G, B, do the following test:

If 6.0*temp3 < 1, color=temp1+(temp2-temp1)*6.0*temp3
tmp1 = 6.0*temp3

tmp1 = (temp2-temp1)
tmp1 = (temp2-temp1)*6.0
tmp1 = (temp2-temp1)*6.0*temp3
*/

fmul	tmp1,temp3,CONST_6.0
fcmpo	cr0,tmp1,CONST_1.0
bge-	0f

fsub	tmp1,temp2,temp1
fmul	tmp1,tmp1,CONST_6.0
fmul	tmp1,tmp1,temp3
fadd	color,temp1,tmp1
blr
0:

/*
Else if 2.0*temp3 < 1, color=temp2
*/

fmul	tmp1,temp3,CONST_2.0
fcmpo	cr0,tmp1,CONST_1.0
bge-	0f
fmr	color,temp2
blr
0:

/*
Else if 3.0*temp3 < 2, color=temp1+(temp2-temp1)*((2.0/3.0)-temp3)*6.0
tmp1 = (temp2-temp1)
tmp2 = (2.0/3.0)-temp3
tmp1 = (temp2-temp1) * ((2.0/3.0)-temp3)
tmp1 = (temp2-temp1) * ((2.0/3.0)-temp3) * 6.0
color = (temp2-temp1) * ((2.0/3.0)-temp3) * 6.0 +temp1
*/

fmul	tmp1,temp3,CONST_3.0
fcmpo	cr0,tmp1,CONST_2.0
bge-	0f
fsub	tmp1,temp2,temp1
fsub	tmp2,CONST_two_3rds,temp3
fmul	tmp1,tmp1,tmp2
fmul	tmp1,tmp1,CONST_6.0
fadd	color,tmp1,temp1
blr
0:

/*
Else color=temp1
*/

fmr	color,temp1

blr

/*-----------------------------------------------------------------------------------------------------------*/

_return:

mtlr	savedLR
lmw	r12,8(r1)
lmfd	4,31,offsetforFPR,1
addi	r1,r1,spaceToSave


# Edit if needed
_original_instruction:
lbz	r0,1392(r27)

