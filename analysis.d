import std.stdio;

import lexer, expression, error;
import distrib, dexpr, util;

alias DefExp=BinaryExp!(Tok!":=");
alias AssignExp=BinaryExp!(Tok!"=");
alias AddExp=BinaryExp!(Tok!"+");
alias SubExp=BinaryExp!(Tok!"-");
alias MulExp=BinaryExp!(Tok!"*");
alias DivExp=BinaryExp!(Tok!"/");
alias UMinusExp=UnaryExp!(Tok!"-");
alias LtExp=BinaryExp!(Tok!"<");
alias LeExp=BinaryExp!(Tok!"<=");
alias GtExp=BinaryExp!(Tok!">");
alias GeExp=BinaryExp!(Tok!">=");
alias EqExp=BinaryExp!(Tok!"==");
alias NeqExp=BinaryExp!(Tok!"!=");
alias Exp=Expression;

private struct Analyzer{
	Distribution dist;
	ErrorHandler err;
	DExpr transformExp(Exp e){
		class Unwind: Exception{ this(){ super(""); } }
		void unwind(){ throw new Unwind(); }
		DExpr doIt(Exp e){
			if(auto id=cast(Identifier)e){
				auto v=dist.lookupVar(id.name);
				if(!v){
					err.error("undefined variable '"~id.name~"'",id.loc);
					unwind();
				}
				return v;
			}
			if(auto ae=cast(AddExp)e) return doIt(ae.e1)+doIt(ae.e2);
			if(auto me=cast(SubExp)e) return doIt(me.e1)-doIt(me.e2);
			if(auto me=cast(MulExp)e) return doIt(me.e1)*doIt(me.e2);
			if(auto de=cast(DivExp)e) return doIt(de.e1)/doIt(de.e2);
			if(auto ume=cast(UMinusExp)e) return -doIt(ume.e);
			if(auto ce=cast(CallExp)e){
				if(auto id=cast(Identifier)ce.e){
					switch(id.name){
					case "Gauss":
						if(ce.args.length!=2){
							err.error("expected two arguments (μ,σ²) to Gauss",ce.loc);
							unwind();
						}
						auto var=dist.getTmpVar("__g");
						dist.distribute(gaussianPDF(var,doIt(ce.args[0]),doIt(ce.args[1])));
						return var;
					case "Uniform": // TODO: handle b<a, b==a
						if(ce.args.length!=2){
							err.error("expected two arguments (a,b) to Uniform",ce.loc);
							unwind();
						}
						auto var=dist.getTmpVar("__u");
						dist.distribute(uniformPDF(var,doIt(ce.args[0]),doIt(ce.args[1])));
						return var;
					case "Bernoulli":
						if(ce.args.length!=1){
							err.error("expected one argument (p) to Bernoulli",ce.loc);
							unwind();
						}
						auto var=dist.getTmpVar("__b");
						dist.distribute(bernoulliPDF(var,doIt(ce.args[0])));
						return var;
					default: break;
					}
				}
			}
			if(auto le=cast(LiteralExp)e){
				if(le.lit.type==Tok!"0")
					return le.lit.int64.dℕ;
			}
			err.error("unsupported",e.loc);
			throw new Unwind();
		}
		try return doIt(e);
		catch(Unwind){ return null; }
	}

	DExpr transformConstr(Exp e){
		class Unwind: Exception{ this(){ super(""); } }
		void unwind(){ throw new Unwind(); }
		DExpr doIt(Exp e){
			enum common=q{
				auto e1=transformExp(b.e1),e2=transformExp(b.e2);
				if(!e1||!e2) unwind();
			};
			with(DIvr.Type)if(auto b=cast(LtExp)e){
				mixin(common);
				return dIvr(lZ,e1-e2);
			}else if(auto b=cast(LeExp)e){
				mixin(common);
				return dIvr(leZ,e1-e2);
			}else if(auto b=cast(GtExp)e){
				mixin(common);
				return dIvr(lZ,e2-e1);
			}else if(auto b=cast(GeExp)e){
				mixin(common);
				return dIvr(leZ,e2-e1);
			}else if(auto b=cast(EqExp)e){
				mixin(common);
				return dIvr(eqZ,e2-e1);
			}else if(auto b=cast(NeqExp)e){
				mixin(common);
				return dIvr(neqZ,e2-e1);
			}
			err.error("unsupported",e.loc);
			throw new Unwind();
		}
		try return doIt(e);
		catch(Unwind){ return null; }
	}
	void analyze(CompoundExp ce)in{assert(!!ce);}body{
		foreach(i,e;ce.s){
			/*writeln("statement: ",e);
			writeln("before: ",dist);
			scope(success) writeln("after: ",dist);*/
			// TODO: visitor?
			if(auto de=cast(DefExp)e){
				if(auto id=cast(Identifier)de.e1){
					if(auto var=dist.declareVar(id.name)){
						auto rhs=transformExp(de.e2);
						dist.initialize(var,rhs?rhs:zero);
					}else err.error("variable already exists",id.loc);
				}else err.error("left hand side of definition should be identifier",de.e1.loc);
			}else if(auto ae=cast(AssignExp)e){
				if(auto id=cast(Identifier)ae.e1){
					if(auto v=dist.lookupVar(id.name)){
						auto rhs=transformExp(ae.e2);
						dist.assign(v,rhs?rhs:zero);
					}else err.error("undefined variable '"~id.name~"'",id.loc);
				}else err.error("left hand side of assignment should be identifier",ae.e1.loc);
			}else if(auto ite=cast(IteExp)e){
				if(auto c=transformConstr(ite.cond)){
					DVar[] ws;
					foreach(v;c.freeVars){
						auto w=dist.getVar(v.name);
						dist.initialize(w,v);
						ws~=w;
					}
					auto dthen=dist.dup(), dothw=dist.dup();
					Analyzer(dthen,err).analyze(ite.then);
					if(ite.othw) Analyzer(dothw,err).analyze(ite.othw);
					dist=dthen.join(dist.vbl,dist.symtab,dist.freeVars,dothw,c);
					foreach(w;ws) dist.marginalize(w);
				}
			}else if(auto re=cast(RepeatExp)e){
				if(auto exp=transformExp(re.num)){
					if(auto num=cast(Dℕ)exp){
						int nerrors=err.nerrors;
						for(ℕ j=0;j<num.c;j++){
							auto dcur=dist.dup();
							Analyzer(dcur,err).analyze(re.bdy);
							dist=dist.join(dist.vbl,dist.symtab,dist.freeVars,dcur,zero);
							if(err.nerrors>nerrors) break;
						}
					}else err.error("repeat expression should be integer constant",re.num.loc);
				}
			}else if(auto re=cast(ReturnExp)e){
				if(i+1==ce.s.length){ // TODO: this does not catch return statements in nested blocks!
					if(auto id=cast(Identifier)re.e){ // TODO: tuple returns
						if(auto v=dist.lookupVar(id.name)){
							while(dist.freeVars.length>1){
								foreach(w;dist.freeVars){
									if(w==v) continue;
									dist.marginalize(w);
									break;
								}
							}
						}else err.error("undefined variable '"~id.name~"'",id.loc);
					}else err.error("only return of variable supported",re.e.loc);
				}else err.error("return statement must be last statement in function",re.loc);
			}else err.error("unsupported",e.loc);
		}
	}
}

void analyze(FunctionDef def,ErrorHandler err){
	auto a=Analyzer(new Distribution,err);
	a.analyze(def.body_);
	writeln(a.dist);
}
