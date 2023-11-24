/*
 * Video/Console functions
 */

Ushort
	Vcols,
	Vlines,
	Vxpos,
	Vypos;
Uchar
	VcursorType,
	VgsIns;			// Insert flag
#define	VLINES	25
#define	VCOLS	80
Vgotoxy(Ushort x, Ushort y)
{
	gotoxy((Vxpos = x)+1, (Vypos = y)+1);
}
void Vputch(Uchar c)
{
	Ushort w;
	switch(c) {
	case '\n' :
	case '\r' :
		putch(c);
		Vxpos = 0;
		return;
	case '\b' :
		putch(c);
		if(Vxpos)
			--Vxpos;
		return; }
	w = VCOLS;
	if(Vypos >= (VLINES-1))
		w = VCOLS-1;
	if(Vxpos < w) {
		putch(c);
		++Vxpos; }
}
// Clear to end of line
void _Vcleol_(void)
{
	Ushort w;
	w = VCOLS;
	if(Vypos >= (VLINES-1))
		w = VCOLS-1;
	while(Vxpos < w)
		Vputch(' ');
}
void Vcleol(void)
{
	Ushort x;
	x = Vxpos;
	_Vcleol_();
	Vgotoxy(x, Vypos);
}
void Vcleos(void)
{
	Ushort x, y;
	x = Vxpos;
	y = Vypos;
	while(Vypos < VLINES) {
		Vgotoxy(Vxpos, Vypos);
		_Vcleol_();
		Vxpos = 0;
		++Vypos; }
	Vgotoxy(x, y);
}
void Vclscr(void)
{
	Vxpos = Vypos = 0;
	Vcleos();
}
// Set cursor type
void Vcursor(Ushort t)
{
	_setcursortype(VcursorType = t);
}
// Initialize the video sub-system
Ushort Vopen(Uchar co)
{
	struct text_info x;
	textmode(C80);
	textattr(co);
	clrscr();
	Vxpos = Vypos = 0;
	gettextinfo(&x);
	Vcols = x.winright;
	Vlines = x.winbottom;
//	Lines2 = (Lines1 = Lines - 1) - 1;
	Vcursor(_NORMALCURSOR);
	VgsIns = 255;
	return (Vcols*100)+Vlines;
}
// Close the video sub-system
void Vclose(void)
{
	textattr(7);
	clrscr();
	_setcursortype(_NORMALCURSOR);
}
// Get a character with special key translatio
Ushort Vgetc(void)
{
	Ushort c;
	switch(c = getch()) {
	case 0x00 : return getch() | 0x100;
	case 0xE0 : return getch() | 0x200;
	case '\r' : c = '\n';
	} return c;
}
// Get key - translating keypad to normal
Ushort Vkey(void)
{
	Ushort k;
	switch(k = Vgetc()) {
	case _KPUA: return _KUA;
	case _KPDA: return _KDA;
	case _KPRA:	return _KRA;
	case _KPLA: return _KLA;
	case _KPHO: return _KHO;
	case _KPEN: return _KEN;
	case _KPPU:	return _KPU;
	case _KPPD:	return _KPD;
	case _KPIN:	return _KIN;
	case _KPDL:	return _KDL; }
	return k;
}
// Get string
Ushort Vgets(Uchar *inp, Ushort len)
{
	Ushort i, l, xp, x, y, k;
	Uchar c, ac, *p;
	Uchar str[128];

	strcpy(str, inp);
	x = Vxpos;
	y = Vypos;
	ac = len >> 8;
	len &= 0x7F;
	xp = 0;
a1:	str[len] = 0;
	Vgotoxy(x, y);
	l = len;
	for(i=c=0; i < len; ++i) {
		if(c) str[i] = 0;
		if(!(k = str[i])) {
			if(!c) {
				l = i;
				c = 255; }
			k = ' '; }
		Vputch(k); }
a2:	_setcursortype(VgsIns ? _SOLIDCURSOR : _NORMALCURSOR);
a3:	Vgotoxy(x+xp, y);
a4:	switch(k = Vkey()) {
case _AF12: exit(-1);
	case _KLA: if(xp) --xp;					goto a3;
	case _KRA: if(xp < l) ++xp;				goto a3;
	case _KHO: xp = 0;						goto a3;
	case _KEN: xp=l;						goto a3;
	case _KIN: VgsIns = VgsIns ? 0 : 255;	goto a2;
	case _KBS: if(!xp)						goto a4;
		--xp;
	case _KDL:	i = xp;
		while(i < len) {
			c = str[i+1];
			str[i++] = c; }
		--l;
		goto a1;
	default:
		if((k & 0x300) && ac) {
			if(ac & 0x01)
				strcpy(inp, str);
			l = k;
			goto ex1; }
		if((k < ' ') || (k > '~'))	goto a4;
		if(xp >= len)				goto a4;
		if(VgsIns) {
			i = len;
			while(i > xp) {
				c = str[i-1];
				str[i--] = c; } }
		if(xp < len)
			str[xp++] = k;
		goto a1;
	case 0x1B : l = -1; goto ex;
	case '\n' :
		strcpy(inp, str);
ex:		if(ac & 0x02)
			l = k;
ex1:	_setcursortype(VcursorType);
		return l; }
}

// Write character to tty with output translactions
void Vputc(Uchar c)
{
	switch(c) {
	case _CL: Vclscr();			return;		// Clear screen
	case _CE: Vcleol();			return;		// Clear to EOL
	case _CD: Vcleos();			return;		// Clear to EOS
	case _SO: textattr(7<<4);	return;		// Hilight-ON
	case _SE: textattr(7);		return;		// Hilight-OFF
	} Vputch(c);
}
void Vputs(Uchar *p)
{
	while(*p) Vputc(*p++);
}
