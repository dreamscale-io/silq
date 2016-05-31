import std.uni, std.array, std.string, std.conv, std.algorithm, std.range;
import dexpr,util;

struct DParser{
	string code;
	void skipWhitespace(){
		while(!code.empty&&code.front.isWhite())
			next();
	}
	dchar cur(){
		skipWhitespace();
		if(code.empty) return 0;
		return code.front;
	}
	void next(){ code.popFront(); }
	void expect(dchar c){
		if(cur()==c) next();
		else throw new Exception("expected '"~to!string(c)~"' at \""~code~"\"");
	}
		
	DExpr parseDIvr(){
		expect('[');
		auto exp=parseDExpr();
		DIvr.Type ty;
		void doIt(DIvr.Type t){
			next();
			if(cur()=='0') expect('0');
			else exp=exp-parseDExpr();
			ty=t;
		}
		switch(cur()) with(DIvr.Type){
			case '=': doIt(eqZ); break;
			case '≠','!':
				if(cur()=='!') next(); doIt(neqZ); break;
			case '<':
				if(code.length>=2&&code[1]=='='){
					next(); doIt(leZ);
				}else doIt(lZ); break;
			case '≤': doIt(leZ); break;
			default: expect('<'); assert(0);
			}
		expect(']');
		return dIvr(ty,exp);
	}
	DExpr parseDDelta(){
		if(code.startsWith("delta")) code=code["delta".length..$];
		else expect('δ');
		bool round=false;
		DVar var=null;
		if(cur()=='_'){ next(); var=parseDVar(); }
		if(cur()=='('){
			round=true;
			next();
		}else expect('[');
		auto expr=parseDExpr();
		expect(round?')':']');
		return var?dDiscDelta(var,expr):dDelta(expr);
	}
		
	DExpr parseSqrt(){
		DExpr e=one/2;
		if(cur()=='∛'){ next(); e=one/3; }
		else if(cur()=='∜'){ next(); e=one/4; }
		else expect('√');
		string arg;
		dchar cur=0;
		string tmp=code;
		for(int i=0;!tmp.empty;){
			dchar c=tmp.front;
			if(i&1){
				if(c=='̅'){
					arg~=cur;
				}else break;
			}else cur=c;
			tmp.popFront();
			if(i&1) code=tmp;
			i++;
		}
		return dParse(arg)^^(one/2);
	}

	DExpr parseDAbs(){
		if(code.startsWith("abs")){
			code=code["abs".length..$];
			expect('(');
			auto arg=parseDExpr();
			expect(')');
			return dAbs(arg);
		}
		expect('|');
		auto arg=parseDExpr();
		expect('|');
		return dAbs(arg);
	}

	DExpr parseLog()in{assert(code.startsWith("log"));}body{
		code=code["log".length..$];
		expect('(');
		auto e=parseDExpr();
		expect(')');
		return dLog(e);
	}

	DExpr parseGaussInt()in{assert(code.startsWith("(d/dx)⁻¹[e^(-x²)]"));}body{
		code=code["(d/dx)⁻¹[e^(-x²)]".length..$];
		expect('(');
		auto e=parseDExpr();
		expect(')');
		return dGaussInt(e);
	}

	DExpr parseDInt(){
		expect('∫');
		expect('d');
		auto iVar=parseDVar();
		auto iExp=parseMult();
		return dInt(iVar,iExp);
	}

	DExpr parseDSum(){
		expect('∑');
		expect('_');
		auto iVar=parseDVar();
		auto iExp=parseMult();
		return dSum(iVar,iExp);
	}

	DExpr parseLim()in{assert(code.startsWith("lim"));}body{
		code=code["lim".length..$];
		expect('[');
		auto var=parseDVar();
		expect('→');
		auto e=parseDExpr();
		expect(']');
		auto x=parseMult();
		return dLim(var,e,x);
	}

	DExpr parseNumber()in{assert('0'<=cur()&&cur()<='9');}body{
		ℕ r=0;
		while('0'<=cur()&&cur()<='9'){
			r=r*10+cast(int)(cur()-'0');
			next();
		}
		if(cur()=='.'){
			string s="0.";
			for(next();'0'<=cur()&&cur()<='9';next()) s~=cur();
			return (s.to!real+toReal(r)).dFloat; // TODO: this is a hack
		}
		return dℕ(r);
	}

	bool isIdentifierChar(dchar c){
		if(c=='δ') return false; // TODO: this is quite crude
		if(c.isAlpha()) return true;
		if(lowDigits.canFind(c)) return true;
		if(c=='_') return true;
		return false;
	}

	string parseIdentifier(){
		skipWhitespace();
		string r;
		while(!code.empty&&(isIdentifierChar(code.front)||!r.empty&&'0'<=code.front()&&code.front<='9')){
			r~=code.front;
			code.popFront();
		}
		if(r=="") expect('ξ');
		return r;
	}

	private DVar varOrBound(string s){
		if(s.startsWith("ξ")){
			auto i=0;
			for(auto rest=s["ξ".length..$];!rest.empty();rest.popFront())
				i=10*i+cast(int)indexOf(lowDigits,rest.front);
			return dBoundVar(i);
		}
		return dVar(s);
	}
	
	DVar parseDVar(){
		string s=parseIdentifier();
		if(cur()=='⃗'){
			next();
			auto fun="q".dFunVar; // TODO: fix!
			return dContextVars(s,fun);
		}
		if(s.startsWith("ξ")){
			auto i=0;
			for(auto rest=s["ξ".length..$];!rest.empty();rest.popFront())
				i=10*i+cast(int)indexOf(lowDigits,rest.front);
			return dBoundVar(i);
		}
		return varOrBound(s);
	}
	DFunVar curFun=null;
	DExpr parseDVarDFun(){
		string s=parseIdentifier();
		if(curFun&&cur()=='⃗'){
			next();
			return dContextVars(s,curFun);
		}
		if(cur()!='('){
			return varOrBound(s);
		}
		auto oldCurFun=curFun; scope(exit) curFun=oldCurFun;
		curFun=dFunVar(s);
		DExpr[] args;
		do{
			next();
			if(cur()!=')') args~=parseDExpr();
		}while(cur()==',');
		expect(')');
		return dFun(curFun,args);
	}

	DExpr parseDLambda(){
		expect('λ');
		auto var=parseDVar();
		expect('.');
		auto expr=parseDExpr();
		return dLambda(var,expr);
	}

	DExpr parseBase(){
		if(code.startsWith("(d/dx)⁻¹[e^(-x²)]")) return parseGaussInt();
		if(cur()=='('){
			next();
			if(cur()==')') return dTuple([]);
			auto r=parseDExpr();
			if(cur()==','){
				auto values=[r];
				while(cur()==','){
					next();
					if(cur()==')') break;
					values~=parseDExpr();
				}
				expect(')');
				return dTuple(values);
			}
			expect(')');
			return r;
		}
		if(cur()=='['){
			int nesting=0;
			foreach(i,c;code){
				if(c=='[') nesting++;
				if(c==']') nesting--;
				if(nesting) continue;
				auto p=DParser(code[i+1..$]);
				if(p.cur()!='(') break;
				next();
				auto var=parseDVar();
				expect('↦');
				auto expr=parseDExpr();
				expect(']');
				expect('(');
				auto len=parseDExpr();
				expect(')');
				return dArray(len,dLambda(var,expr));
			}
		}
		if(cur()=='{'){
			next();
			DExpr[string] values;
			while(cur()=='.'){
				next();
				auto f=parseIdentifier();
				expect('↦');
				auto e=parseDExpr();
				values[f]=e;
				if(cur()==',') next();
				else break;
			}
			expect('}');
			return dRecord(values);
		}
		if(cur()=='∞'){ next(); return dInf; }
		if(cur()=='[') return parseDIvr();
		if(cur()=='δ'||code.startsWith("delta")) return parseDDelta();
		if(cur()=='∫') return parseDInt();
		if(cur()=='∑') return parseDSum();
		if(cur()=='λ') return parseDLambda();
		if(util.among(cur(),'√','∛','∜')) return parseSqrt();
		if(cur()=='|'||code.startsWith("abs")) return parseDAbs();
		if(code.startsWith("log")) return parseLog();
		if(code.startsWith("lim")) return parseLim();
		if(cur()=='⅟'){
			next();
			return 1/parseFactor();
		}
		if('0'<=cur()&&cur()<='9')
			return parseNumber();
		if(cur()=='e'){
			next();
			return dE;
		}
		if(cur()=='π'){
			next();
			return dΠ;
		}
		return parseDVarDFun();
	}

	DExpr parseIndex(){
		auto e=parseBase();
		while(cur()=='['||cur()=='{'||cur()=='.'){
			if(cur()=='['){
				next();
				auto i=parseDExpr();
				if(cur()=='↦'){
					next();
					auto n=parseDExpr();
					e=dIUpdate(e,i,n);
				}else e=dIndex(e,i);
				expect(']');
			}else if(cur()=='{'){
				next();
				expect('.');
				auto f=parseIdentifier();
				expect('↦');
				auto n=parseDExpr();
				e=dRUpdate(e,f,n);
				expect('}');
			}else{
				assert(cur()=='.');
				next();
				auto i=parseIdentifier();
				e=dField(e,i);
			}
		}
		return e;
	}
	

	DExpr parseDPow(){
		auto e=parseIndex();
		if(cur()=='^'){
			next();
			return e^^parseFactor();
		}
		ℕ exp=0;
		if(highDigits.canFind(cur())){
			do{
				exp=10*exp+highDigits.indexOf(cur());
				next();
			}while(highDigits.canFind(cur));
			return e^^exp;
		}
		return e;
	}

	DExpr parseFactor(){
		if(cur()=='-'){
			next();
			return -parseFactor();
		}
		return parseDPow();
	}

	bool isMultChar(dchar c){
		return "·*"d.canFind(c);
	}
	bool isDivChar(dchar c){
		return "÷/"d.canFind(c);
	}

	DExpr parseMult(){
		DExpr f=parseFactor();
		while(isMultChar(cur())||isDivChar(cur())){
			if(isMultChar(cur())){
				next();
				f=f*parseFactor();
			}else{
				next();
				f=f/parseFactor();
			}
		}
		return f;
	}

	DExpr parseAdd(){
		DExpr s=parseMult();
		while(cur()=='+'||cur()=='-'){
			auto x=cur();
			next();
			auto c=parseMult();
			if(x=='-') c=-c;
			s=s+c;
		}
		return s;
	}

	DExpr parseDExpr(){
		return parseAdd();
	}
}
DExpr dParse(string s){ // TODO: this is work in progress, usually updated in order to speed up debugging
	return DParser(s).parseDExpr();
}

