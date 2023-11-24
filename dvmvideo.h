/*
 * Micro-C video definitions for DVM
 *
 * ?COPY.TXT 2020 Dave Dunfield
 * **See COPY.TXT**.
 */

// Special characters recognized by Vputc
#define _CL 	0x85			/* clear entire display */
#define _CD		0x86			/* clear to end of display */
#define _CE 	0x87			/* clear to end of line */
#define _SO 	0x88			/* Begin standout mode */
#define _SE 	0x89			/* end standout mode */

// Special keys returned by Vgetc() and Vgetk()
#define	_KBS	0x008
#define	_K1		0x13B
#define	_K2		0x13C
#define	_K3		0x13D
#define	_K4		0x13E
#define	_K5		0x13F
#define	_K6		0x140
#define	_K7		0x141
#define	_K8		0x142
#define	_K9		0x143
#define	_K10	0x144
#define	_K11	0x285
#define	_K12	0x286
#define	_KUA	0x248
#define	_KDA	0x250
#define	_KLA	0x24B
#define	_KRA	0x24D
#define	_KHO	0x247
#define	_KEN	0x24F
#define	_KPU	0x249
#define	_KPD	0x251
#define	_KIN	0x252
#define	_KDL	0x253

#define	_CBS	0x07F
#define	_CF1	0x15E
#define	_CF2	0x15F
#define	_CF3	0x160
#define	_CF4	0x161
#define	_CF5	0x162
#define	_CF6	0x163
#define	_CF7	0x164
#define	_CF8	0x165
#define	_CF9	0x166
#define	_CF10	0x167
#define	_CF11	0x289
#define	_CF12	0x28A
#define	_CUA	0x28D
#define	_CDA	0x291
#define	_CLA	0x273
#define	_CRA	0x274
#define	_CHO	0x277
#define	_CEN	0x275
#define	_CPU	0x286
#define	_CPD	0x276
#define	_CIN	0x292
#define	_CDL	0x293
#define	_CTAB	0x194		// ^TAB

#define	_AF1	0x168
#define	_AF2	0x169
#define	_AF3	0x16A
#define	_AF4	0x16B
#define	_AF5	0x16C
#define	_AF6	0x16D
#define	_AF7	0x16E
#define	_AF8	0x16F
#define	_AF9	0x170
#define	_AF10	0x171
#define	_AF11	0x28B
#define	_AF12	0x28C
#define	_AUA	0x198
#define	_ADA	0x1A0
#define	_ALA	0x19B
#define	_ARA	0x19D
#define	_AHO	0x197
#define	_AEN	0x19F
#define	_APU	0x199
#define	_APD	0x1A1
#define	_AIN	0x1A2
#define	_ADL	0x1A3

#define	_RAIN	0x197

// Keypad specific keys: Vgetk() maps to standard keys
#define	_KPUA	0x148
#define	_KPDA	0x150
#define	_KPLA	0x14B
#define	_KPRA	0x14D
#define	_KPHO	0x147
#define	_KPEN	0x14F
#define	_KPPU	0x149
#define	_KPPD	0x151
#define	_KPIN	0x152
#define	_KPDL	0x153
#define	_CPSL	0x195	// Keypad ^/

// Colors used by Vinit(), Vcolor(), VFcolor() and VBcolor()
// Vinit() and Vcolor() use (background<<8) | foreground
#define BLACK			0
#define BLUE			1
#define GREEN			2
#define CYAN			3
#define RED				4
#define MAGENTA			5
#define BROWN			6
#define LIGHTGRAY		7
#define DARKGRAY		8
#define LIGHTBLUE		9
#define LIGHTGREEN		10
#define LIGHTCYAN		11
#define LIGHTRED		12
#define LIGHTMAGENTA	13
#define YELLOW			14
#define WHITE			15
#define BLINK			128	// Useless, background uses high intensity colors.

// Cursor types used by Vcursor()
#define CURSOR_NONE		0
#define CURSOR_BLOCK	1
#define CURSOR_LINE		2

// Common video colors
#define	NORMAL		0x07		// White on Black
#define REVERSE		0x70		// Black on White
