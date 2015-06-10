import std.conv;
import hashtable, util;

import std.algorithm, std.array;

enum Precedence{
	none,
	plus,
	uminus,
	intg,
	mult,
	pow,
	invalid,
}

abstract class DExpr{
	override string toString(){
		return toStringImpl(Precedence.none);
	}
	abstract string toStringImpl(Precedence prec);

	abstract DExpr substitute(DVar var,DExpr e);
	abstract DExpr incDeBruin(int di);
	abstract int freeVarsImpl(scope int delegate(DVar));
	final freeVars(){
		static struct FreeVars{ // TODO: move to util?
			DExpr self;
			int opApply(scope int delegate(DVar) dg){
				return self.freeVarsImpl(dg);
			}
		}
		return FreeVars(this);
	}
	final bool hasFreeVar(DVar var){
		foreach(v;freeVars) if(v is var) return true;
		return false;
	}
	DExpr solveFor(DVar var,DExpr rhs){ return null; }

	bool isFraction(){ return false; }
	ℕ[2] getFraction(){ assert(0,"not a fraction"); }

	// helpers for construction of DExprs:
	enum ValidUnary(string s)=s=="-";
	enum ValidBinary(string s)=["+","-","*","/","^^"].canFind(s);
	template UnaryCons(string s)if(ValidUnary!s){
		static assert(s=="-");
		alias UnaryCons=dUMinus;
	}
	template BinaryCons(string s)if(ValidBinary!s){
		static if(s=="+") alias BinaryCons=dPlus;
		else static if(s=="-") alias BinaryCons=dMinus;
		else static if(s=="*") alias BinaryCons=dMult;
		else static if(s=="/") alias BinaryCons=dDiv;
		else static if(s=="^^") alias BinaryCons=dPow;
		else static assert(0);
	}
	final opUnary(string op)()if(op=="-"){ return UnaryCons!op(this); }
	final opBinary(string op)(DExpr e)if(ValidBinary!op){
		return BinaryCons!op(this,e);
	}
	final opBinary(string op)(long e)if(ValidBinary!op){
		return mixin("this "~op~" e.dℕ");
	}
	final opBinaryRight(string op)(long e)if(ValidBinary!op){
		return mixin("e.dℕ "~op~" this");
	}

	mixin template Constant(){
		override int freeVarsImpl(scope int delegate(DVar) dg){ return 0; }
		override DExpr substitute(DVar var,DExpr e){ assert(var !is this); return this; }
		override DExpr incDeBruin(int di){ return this; }
	}
}
alias DExprSet=SetX!DExpr;
class DVar: DExpr{
	string name;
	private this(string name){ this.name=name; }
	override string toStringImpl(Precedence prec){ return name; }

	override int freeVarsImpl(scope int delegate(DVar) dg){ return dg(this); }
	override DExpr substitute(DVar var,DExpr e){ return this is var?e:this; }
	override DExpr incDeBruin(int di){ return this; }
	override DExpr solveFor(DVar var,DExpr e){
		if(this is var) return e;
		return null;
	}
}
DVar dVar(string name){ return new DVar(name); }

class DDeBruinVar: DVar{
	int i;
	private this(int i){ this.i=i; super("ξ"~lowNum(i)); }
	override DDeBruinVar incDeBruin(int di){ return dDeBruinVar(i+di); }
	
}
DDeBruinVar[int] uniqueMapDeBruin;
DDeBruinVar dDeBruinVar(int i){
	return i !in uniqueMapDeBruin ?
		uniqueMapDeBruin[i]=new DDeBruinVar(i):
		uniqueMapDeBruin[i];
}


class Dℕ : DExpr{
	ℕ c;
	private this(ℕ c){ this.c=c; }
	override string toStringImpl(Precedence prec){
		string r=text(c);
		if(prec>Precedence.uminus&&c<0)
			r="("~r~")";
		return r;
	}
	override bool isFraction(){ return true; }
	override ℕ[2] getFraction(){ return [c,ℕ(1)]; }

	mixin Constant;
}

Dℕ[ℕ] uniqueMapDℕ;
DExpr dℕ(ℕ c){
	if(c in uniqueMapDℕ) return uniqueMapDℕ[c];
	return uniqueMapDℕ[c]=new Dℕ(c);
}
DExpr dℕ(long c){ return dℕ(ℕ(c)); }

class DE: DExpr{
	override string toStringImpl(Precedence prec){ return "e"; }
	mixin Constant;
}
private static DE theDE;
@property DE dE(){ return theDE?theDE:(theDE=new DE); }

class DΠ: DExpr{
	override string toStringImpl(Precedence prec){ return "π"; }
	mixin Constant;
}
private static DΠ theDΠ;
@property DΠ dΠ(){ return theDΠ?theDΠ:(theDΠ=new DΠ); }

private static DExpr theOne;
@property DExpr one(){ return theOne?theOne:(theOne=1.dℕ);}

private static DExpr theZero;
@property DExpr zero(){ return theZero?theZero:(theZero=0.dℕ);}

abstract class DOp: DExpr{
	abstract @property string symbol();
	bool rightAssociative(){ return false; }
	abstract @property Precedence precedence();
	protected final string addp(Precedence prec, string s, Precedence myPrec=Precedence.invalid){
		if(myPrec==Precedence.invalid) myPrec=precedence;
		return prec > myPrec||rightAssociative&&prec==precedence? "(" ~ s ~ ")":s;
	}
}

abstract class DCommutAssocOp: DOp{
	DExprSet operands;
	protected mixin template Constructor(){ private this(DExprSet e)in{assert(e.length>1); }body{ operands=e; } }
	override string toStringImpl(Precedence prec){
		string r;
		auto ops=operands.array.map!(a=>a.toStringImpl(precedence)).array;
		sort(ops);
		foreach(o;ops) r~=symbol~o;
		return addp(prec, r[symbol.length..$]);
	}
}

DExprSet shallow(T)(DExprSet arg){
	DExprSet r;
	foreach(x;arg){
		if(auto t=cast(T)x){
			foreach(y;t.operands){
				T.insert(r,y);
			}
		}
	}
	if(!r.length) return arg;
	foreach(x;arg) if(!cast(T)x) T.insert(r,x);
	return r;
}

MapX!(TupleX!(typeof(typeid(DExpr)),DExprSet),DExpr) uniqueMapCommutAssoc;
MapX!(TupleX!(typeof(typeid(DExpr)),DExpr,DExpr),DExpr) uniqueMapNonCommutAssoc;

auto uniqueDExprCommutAssoc(T)(DExprSet e){
	auto t=tuplex(typeid(T),e);
	if(t in uniqueMapCommutAssoc) return cast(T)uniqueMapCommutAssoc[t];
	auto r=new T(e);
	uniqueMapCommutAssoc[t]=r;
	return r;
}
auto uniqueDExprNonCommutAssoc(T)(DExpr a, DExpr b){
	auto t=tuplex(typeid(T),a,b);
	if(t in uniqueMapNonCommutAssoc) return cast(T)uniqueMapNonCommutAssoc[t];
	auto r=new T(a,b);
	uniqueMapNonCommutAssoc[t]=r;
	return r;
}
MapX!(TupleX!(typeof(typeid(DExpr)),DExpr),DExpr) uniqueMapUnary;
auto uniqueDExprUnary(T)(DExpr a){
	auto t=tuplex(typeid(T),a);
	if(t in uniqueMapUnary) return cast(T)uniqueMapUnary[t];
	auto r=new T(a);
	uniqueMapUnary[t]=r;
	return r;
}
string makeConstructorCommutAssoc(T)(){
	enum Ts=__traits(identifier, T);
	return "auto " ~ lowerf(Ts)~"(DExprSet f){ auto fsh=f.shallow!"~__traits(identifier,T)~";"
		~"if(fsh.length==1) return fsh.element;"
		~"if(auto r="~Ts~".constructHook(fsh)) return r;"
		~"return uniqueDExprCommutAssoc!("~__traits(identifier,T)~")(fsh);"
		~"}"
		~"auto " ~ lowerf(Ts)~"(DExpr e1,DExpr e2){"
		~"  DExprSet a;"~Ts~".insert(a,e1);"~Ts~".insert(a,e2);"
		~"  return "~lowerf(Ts)~"(a);"
		~"}";
}

string makeConstructorNonCommutAssoc(T)(){
	enum Ts=__traits(identifier, T);
	return "auto " ~ lowerf(Ts)~"(DExpr e1, DExpr e2){ "
		~"static if(__traits(hasMember,"~Ts~",`constructHook`))"
		~"  if(auto r="~Ts~".constructHook(e1,e2)) return r;"
		~"return uniqueDExprNonCommutAssoc!("~__traits(identifier,T)~")(e1,e2);"
		~"}";
}

string makeConstructorUnary(T)(){
	return "auto " ~ lowerf(__traits(identifier, T))~"(DExpr e){ return uniqueDExprUnary!("~__traits(identifier,T)~")(e); }";
}


class DPlus: DCommutAssocOp{
	alias summands=operands;
	mixin Constructor;
	override @property Precedence precedence(){ return Precedence.plus; }
	override @property string symbol(){ return "+"; }

	override int freeVarsImpl(scope int delegate(DVar) dg){
		foreach(a;operands)
			if(auto r=a.freeVarsImpl(dg))
				return r;
		return 0;
	}
	override DExpr substitute(DVar var,DExpr e){
		DExprSet res;
		foreach(s;summands) insert(res,s.substitute(var,e));
		return dPlus(res);
	}
	override DExpr incDeBruin(int di){
		DExprSet res;
		foreach(s;summands) insert(res,s.incDeBruin(di));
		return dPlus(res);
	}
	override DExpr solveFor(DVar var,DExpr e){
		auto ow=splitPlusAtVar(this,var);
		if(cast(DPlus)ow[1]) return null; // TODO
		return ow[1].solveFor(var,e-ow[0]);
	}

	static void insert(ref DExprSet summands,DExpr summand)in{assert(!!summand);}body{
		if(auto dp=cast(DPlus)summand){
			foreach(s;dp.summands)
				insert(summands,s);
			return;
		}
		static DExpr combine(DExpr e1,DExpr e2){
			if(e1 is zero) return e2;
			if(e2 is zero) return e1;
			if(e1 is e2) return 2*e1;
			if(e1.isFraction()&&e2.isFraction()){
				auto nd1=e1.getFraction();
				auto nd2=e2.getFraction();
				return dℕ(nd1[0]*nd2[1]+nd2[0]*nd1[1])/dℕ(nd1[1]*nd2[1]);
			}
			auto common=intersect(e1.factors.setx,e2.factors.setx); // TODO: optimize?
			if(common.length){
				auto cm=dMult(common);
				if(!cm.isFraction())
					return (e1/cm+e2/cm)*cm;
			}
			return null;
		}
		// TODO: use suitable data structures
		foreach(s;summands){
			if(auto nws=combine(s,summand)){
				summands.remove(s);
				insert(summands,nws);
				return;
			}
		}
		assert(summand !in summands);
		summands.insert(summand);
	}
	static DExpr constructHook(DExprSet operands){
		if(operands.length==0) return zero;
		return null;
	}
}

class DMult: DCommutAssocOp{
	alias factors=operands;
	//mixin Constructor;
	private this(DExprSet e)in{assert(e.length>1); }body{ assert(one !in e,text(e)); operands=e; }
	override @property Precedence precedence(){ return Precedence.mult; }
	override @property string symbol(){ return "·"; }
	override string toStringImpl(Precedence prec){
		// TODO: use suitable data structures
		foreach(f;factors){
			if(auto c=cast(Dℕ)f){
				if(c.c<0){
					return addp(prec,"-"~(-this).toStringImpl(Precedence.uminus),Precedence.uminus);
				}
			}
		}
		return super.toStringImpl(prec);
	}

	override int freeVarsImpl(scope int delegate(DVar) dg){
		foreach(a;operands)
			if(auto r=a.freeVarsImpl(dg))
				return r;
		return 0;
	}
	override DExpr substitute(DVar var,DExpr e){
		DExprSet res;
		foreach(f;factors) insert(res,f.substitute(var,e));
		return dMult(res);
	}
	override DExpr incDeBruin(int di){
		DExprSet res;
		foreach(f;factors) insert(res,f.incDeBruin(di));
		return dMult(res);
	}
	override DExpr solveFor(DVar var,DExpr e){
		auto ow=splitMultAtVar(this,var);
		if(cast(DMult)ow[1]) return null; // TODO
		return ow[1].solveFor(var,e/ow[0]);
	}

	override bool isFraction(){ return factors.all!(a=>a.isFraction()); }
	override ℕ[2] getFraction(){
		ℕ n=1,d=1;
		foreach(f;factors){
			auto nd=f.getFraction();
			n*=nd[0], d*=nd[1];
		}
		return [n,d];
	}

	static void insert(ref DExprSet factors,DExpr factor)in{assert(!!factor);}body{
		if(zero in factors||factor is zero){ factors.clear(); factors.insert(zero); return; }
		if(auto dm=cast(DMult)factor){
			foreach(f;dm.factors)
				insert(factors,f);
			return;
		}
		// TODO: use suitable data structures
		static DExpr combine(DExpr e1,DExpr e2){
			if(e1 is one) return e2;
			if(e2 is one) return e1;
			if(e1 is e2) return e1^^2;
			if(e2.isFraction()) swap(e1,e2);
			if(e1.isFraction()){
				auto nd1=e1.getFraction();
				if(nd1[0]==1&&nd1[1]==1) return e2;
				if(e2.isFraction()){
					auto nd2=e2.getFraction();
					auto n=nd1[0]*nd2[0],d=nd1[1]*nd2[1];
					auto g=gcd(n,d);
					if(g==1&&(nd1[0]==1||nd2[0]==1)) return null;
					return dℕ(n/g)/dℕ(d/g);
				}
				if(nd1[0]==-1&&nd1[1]==1){ // TODO: do for all constants?
					if(auto p=cast(DPlus)e2){
						DExprSet summands;
						foreach(s;p.summands) summands.insert(-s);
						return dPlus(summands);
					}
				}
			}
			if(e2.isFraction()){
				auto nd2=e2.getFraction();
				if(nd2[0]==1&&nd2[1]==1) return e1;
			}
			if(cast(DPow)e2) swap(e1,e2);
			if(auto p=cast(DPow)e1){
				if(p.operands[0] is e2)
					return p.operands[0]^^(p.operands[1]+1);
				if(auto d=cast(Dℕ)p.operands[0]){
					if(auto e=cast(Dℕ)e2){
						if(d.c==-e.c)
							return -d^^(p.operands[1]+1);
					}
				}
				if(auto pf=cast(DPow)e2){
					if(p.operands[0] is pf.operands[0])
						return p.operands[0]^^(p.operands[1]+pf.operands[1]);
				}				
			}
			return null;
		}
		foreach(f;factors){
			if(auto nwf=combine(f,factor)){
				factors.remove(f);
				if(factors.length||nwf !is one)
					insert(factors,nwf);
				return;
			}
		}
		assert(factors.length==1||one !in factors);
		factors.insert(factor);
	}
	static DExpr constructHook(DExprSet operands){
		if(operands.length==0) return one;
		return null;
	}
}

mixin(makeConstructorCommutAssoc!DMult);
mixin(makeConstructorCommutAssoc!DPlus);

auto operands(T)(DExpr x){
	static struct Operands{
		DExpr x;
		int opApply(scope int delegate(DExpr) dg){
			if(auto m=cast(T)x){
				foreach(f;m.operands)
					if(auto r=dg(f))
						return r;
				return 0;
			}else return dg(x);
		}
	}
	return Operands(x);
}
alias factors=operands!DMult;
alias summands=operands!DPlus;

DExpr dMinus(DExpr e1,DExpr e2){ return e1+-e2; }

abstract class DBinaryOp: DOp{
	DExpr[2] operands;
	protected mixin template Constructor(){ private this(DExpr e1, DExpr e2){ operands=[e1,e2]; } }
	override string toStringImpl(Precedence prec){
		return addp(prec, operands[0].toStringImpl(precedence) ~ symbol ~ operands[1].toStringImpl(precedence));
	}
	override int freeVarsImpl(scope int delegate(DVar) dg){
		foreach(a;operands)
			if(auto r=a.freeVarsImpl(dg))
				return r;
		return 0;
	}
}

class DPow: DBinaryOp{
	mixin Constructor;
	override Precedence precedence(){ return Precedence.pow; }
	override @property string symbol(){ return "^"; }
	override bool rightAssociative(){ return true; }

	override bool isFraction(){ return cast(Dℕ)operands[0] && cast(Dℕ)operands[1]; }
	override ℕ[2] getFraction(){
		auto d=cast(Dℕ)operands[0];
		assert(d && operands[1] is -one);
		return [ℕ(1),d.c];
	}

	override string toStringImpl(Precedence prec){
		// TODO: always use ⅟ if negative factor in exponent
		if(auto c=cast(Dℕ)operands[1]){
			if(c.c==-1){
				if(auto d=cast(Dℕ)operands[0])
					if(2<=d.c&&d.c<=6)
						return addp(prec,text("  ½⅓¼⅕⅙"d[d.c.toLong()]),Precedence.mult);
				return addp(prec,"⅟"~operands[0].toStringImpl(Precedence.mult),Precedence.mult);
			}
			return addp(prec,operands[0].toStringImpl(Precedence.pow)~highNum(c.c));
		}
		if(auto c=cast(DPow)operands[1]){
			if(auto e=cast(Dℕ)c.operands[1]){
				if(e.c==-1){
					if(auto d=cast(Dℕ)c.operands[0]){
						if(2<=d.c&&d.c<=4)
							return text("  √∛∜"d[d.c.toLong()],overline(operands[0].toString()));
					}
				}
			}
		}
		return super.toStringImpl(prec);
	}

	override DExpr substitute(DVar var,DExpr e){
		return operands[0].substitute(var,e)^^operands[1].substitute(var,e);
	}
	override DExpr incDeBruin(int di){
		return operands[0].incDeBruin(di)^^operands[1].incDeBruin(di);
	}

	static DExpr constructHook(DExpr e1,DExpr e2){
		if(e1 !is -one) if(auto c=cast(Dℕ)e1) if(c.c<0) return (-1)^^e2*dℕ(-c.c)^^e2;
		if(auto m=cast(DMult)e1){ // TODO: do we really want auto-distribution?
			DExprSet factors;
			foreach(f;m.operands){
				DMult.insert(factors,f^^e2);
			}
			return dMult(factors);
		}
		if(auto p=cast(DPow)e1) return p.operands[0]^^(p.operands[1]*e2);
		if(e1 is one||e2 is zero) return one;
		if(e1 is -one && e2 is -one) return -one;
		if(e2 is one) return e1;
		if(auto d=cast(Dℕ)e2){
			if(auto c=cast(Dℕ)e1){
				if(d.c>0) return dℕ(pow(c.c,d.c));
				else if(d.c!=-1) return dℕ(pow(c.c,-d.c))^^-1;
			}
		}
		return null;
	}
}

mixin(makeConstructorNonCommutAssoc!DPow);
DExpr dDiv(DExpr e1,DExpr e2){ return e1*e2^^-1; }

abstract class DUnaryOp: DOp{
	DExpr operand;
	protected mixin template Constructor(){ private this(DExpr e){ operand=e; } }
	override string toStringImpl(Precedence prec){
		return addp(prec, symbol~operand.toStringImpl(precedence));
	}
}
DExpr dUMinus(DExpr e){ return -1*e; }

class DIvr: DExpr{ // iverson brackets
	enum Type{ // TODO: remove redundancy?
		eqZ,
		neqZ,
		lZ,
		leZ,
	}
	Type type;
	DExpr e;
	this(Type type,DExpr e){ this.type=type; this.e=e; }

	override int freeVarsImpl(scope int delegate(DVar) dg){ return e.freeVarsImpl(dg); }
	override DExpr substitute(DVar var,DExpr exp){ return dIvr(type,e.substitute(var,exp)); }
	override DExpr incDeBruin(int di){ return dIvr(type,e.incDeBruin(di)); }

	override string toStringImpl(Precedence prec){
		with(Type) return "["~e.toString()~(type==eqZ?"=":type==neqZ?"≠":type==lZ?"<":"≤")~"0]";
	}
}
MapX!(DExpr,DExpr)[DIvr.Type.max+1] uniqueMapDIvr;
DExpr dIvr(DIvr.Type type,DExpr e){
	if(e in uniqueMapDIvr[type]) return uniqueMapDIvr[type][e];
	auto r=new DIvr(type,e);
	uniqueMapDIvr[type][e]=r;
	return r;

}

class DDelta: DExpr{ // (not exactly a dirac delta function: integral is invariant under scaling)
	DExpr e;
	private this(DExpr e){ this.e=e; }
	override string toStringImpl(Precedence prec){ return "δ̅["~e.toString()~"]"; }

	override int freeVarsImpl(scope int delegate(DVar) dg){ return e.freeVarsImpl(dg); }
	override DExpr substitute(DVar var,DExpr exp){ return dDelta(e.substitute(var,exp)); }
	override DExpr incDeBruin(int di){ return dDelta(e.incDeBruin(di)); }
}

mixin(makeConstructorUnary!DDelta);

DExpr[2] splitPlusAtVar(DExpr e,DVar var){
	DExprSet within;
	DExprSet outside;
	foreach(s;e.summands){
		if(s.hasFreeVar(var)) DPlus.insert(within,s);
		else DPlus.insert(outside,s);
	}
	return [dPlus(outside),dPlus(within)];
}

DExpr[2] splitMultAtVar(DExpr e,DVar var){
	DExprSet within;
	DExprSet outside;
	foreach(f;e.factors){
		if(f.hasFreeVar(var)){
			if(auto p=cast(DPow)f){
				if(p.operands[0].hasFreeVar(var)){
					DMult.insert(within,f);
				}else{
					auto ow=splitPlusAtVar(p.operands[1],var);
					DMult.insert(outside,p.operands[0]^^ow[0]);
					DMult.insert(within,p.operands[0]^^ow[1]);
				}
			}else DMult.insert(within,f);
		}else DMult.insert(outside,f);
	}
	return [dMult(outside),dMult(within)];
}

class DInt: DOp{
	private{
		DDeBruinVar var;
		DExpr expr;
		this(DDeBruinVar var,DExpr expr){ this.var=var; this.expr=expr; }
	}
	DExpr getExpr(DVar var){
		assert(this.var is dDeBruinVar(1));
		return expr.substitute(this.var,var).incDeBruin(-1);
	}
	override @property Precedence precedence(){ return Precedence.intg; }
	override @property string symbol(){ return "∫"; }
	override string toStringImpl(Precedence prec){
		return addp(prec,symbol~"d"~var.toString()~expr.toStringImpl(precedence));
	}
	static DExpr constructHook(DVar var,DExpr expr){
		assert(!cast(DDeBruinVar)var);
		if(auto m=cast(DPlus)expr){
			DExprSet summands;
			foreach(s;m.summands)
				DPlus.insert(summands,dInt(var,s));
			return dPlus(summands);
		}
		auto ow=expr.splitMultAtVar(var);
		if(ow[0] !is one) return ow[0]*dInt(var,ow[1]);
		foreach(f;expr.factors){
			if(!f.hasFreeVar(var)) continue;
			if(auto d=cast(DDelta)f){
				if(auto s=d.e.solveFor(var,zero))
					return (expr/f).substitute(var,s);
			}
		}
		if(expr!is one && !expr.hasFreeVar(var)) return expr*dInt(var,one); // (infinite integral)
		return null;
	}
	override int freeVarsImpl(scope int delegate(DVar) dg){
		return expr.freeVarsImpl(v=>v is var?0:dg(v));
	}
	override DExpr substitute(DVar var,DExpr e){
		if(this.var is var) return this;
		return dInt(this.var,expr.substitute(var,e));
	}
	override DExpr incDeBruin(int di){
		return dInt(var.incDeBruin(di),expr.incDeBruin(di));
	}
}

MapX!(TupleX!(typeof(typeid(DExpr)),DDeBruinVar,DExpr),DExpr) uniqueMapBinding;
auto uniqueBindingDExpr(T)(DDeBruinVar v,DExpr a){
	auto t=tuplex(typeid(T),v,a);
	if(t in uniqueMapBinding) return cast(T)uniqueMapBinding[t];
	auto r=new T(v,a);
	uniqueMapBinding[t]=r;
	return r;
}

DExpr dInt(DVar var,DExpr expr){
	if(auto dbvar=cast(DDeBruinVar)var) return uniqueBindingDExpr!DInt(dbvar,expr);
	if(auto r=DInt.constructHook(var,expr)) return r;
	auto dbvar=dDeBruinVar(1);
	expr=expr.incDeBruin(1).substitute(var,dbvar);
	return uniqueBindingDExpr!DInt(dbvar,expr);
}
