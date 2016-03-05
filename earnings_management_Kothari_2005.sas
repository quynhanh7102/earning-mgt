/*

	Earnings management, Kothari 2005 model

	tac = a0 + a1 1/TAt-1 + a2(chSales - chREC) + a3PPE + a4ROA + error.

	tac:		Total accruals, computed as net profit after tax before extraordinary items 
				less cash flows from operations	
	1/TAt-1:	Inverse of beginning of year total assets
	chSales:	Change in net sales revenue
	chREC: 		Change in net receivables
	PPE:		Gross property, plant, and equipment
	ROA:		Return on assets. 

	All variables are scaled by beginning of year total assets (except ROA) to control for 
	heteroscedasticity.

	Variables used Compustat Funda
	AT:		Total assets
	IB: 	Income Before Extraordinary Items
	IBC: 	Income Before Extraordinary Items (Cash Flow) (used if IB is missing)
	OANCF: 	Operating Activities - Net Cash Flow
	PPEGT:	Property, Plant and Equipment - Total (Gross)
	RECT: 	Receivables - Total
	SALE:	Sales
*/

/* Assign directory for output */
%let projectDir = F:/temp/;

/* Include %array and %do_over */
filename m1 url 'https://gist.github.com/JoostImpink/c22197c93ecd27bbf7ef';
%include m1;

/* Get Funda variables */
%let fundaVars = at ib ibc oancf ppegt rect sale ;

data da.a_funda (keep = key gvkey fyear datadate sich &fundaVars);
set comp.funda;
/* Period */
if 2005 <= fyear <= 2014;
/* Generic filter */
if indfmt='INDL' and datafmt='STD' and popsrc='D' and consol='C' ;
/* Firm-year identifier */
key = gvkey || fyear;
/* Keep if sale > 0, at > 0 */
if sale > 0 and at > 0;
/* Use Income Before Extraordinary Items (Cash Flow) if ib is missing */
if ib =. then ib=ibc;
run;

/* Lagged values for: at sale rect invt roa */
%let lagVars = at sale rect;

/* Self join to get lagged values at_l, sale_l, rect_l */
proc sql;
 create table da.b_funda as select a.*, %do_over(values=&lagVars, between=comma, phrase=b.? as ?_l)
 from da.a_funda a, da.a_funda b
 where a.gvkey = b.gvkey and a.fyear-1 = b.fyear;
quit;

/* Construct additional variables */
data da.b_funda;
set da.b_funda;
/* 2-digit SIC  */
SIC2 = int(sich/100);
/* variables */
tac        = (ib - oancf)/at_l;  /* alternative: tac        = (ib-oancf+xidoc)/at_l */
inv_at_l  = 1 / at_l;
rev       = sale / at_l;
drev      = (sale - sale_l) / at_l;
drevadj   = ( (sale - sale_l) - (rect - rect_l) )/at_l;
ppe       = ppegt / at_l;
roa = ib/ at; /* net income before extraordinary items */
/* these variables may not be missing (cmiss counts missing variables)*/
if cmiss  (of tac inv_at_l drevadj ppe roa) eq 0;
run;

/* Winsorize  */
%let winsVars = tac inv_at_l rev drev drevadj ppe roa  ; 
%winsor(dsetin=da.b_funda, dsetout=da.b_funda_wins, /*byvar=, */ vars=&winsVars, type=winsor, pctl=1 99);

/* Regression by industry-year -- added edf for degrees of freemdom 
 edf + #params (4) will equal the number of obs (no need for proc univariate to count) */
proc sort data=da.b_funda_wins; by fyear sic2;run;
proc reg data=da.b_funda_wins noprint edf outest=da.c_parms;
model tac = inv_at_l drevadj ppe roa;      
by fyear sic2;
run;

/* Append fitted value, error and abs error to dataset */
proc sql;
 create table da.d_model1 as 
 /* fitted value computed as sum of coefficients in b multiplied by values in a */
 select a.*, b.intercept + %do_over(values=inv_at_l drevadj ppe roa, between=%str(+), phrase=a.? * b.?) as fitted,
 /* abnormal accruals are ta - fitted */
 a.tac - calculated fitted as DA, 
 /* absolute abnormal accruals */
 abs (calculated DA) as ABSDA
 from da.b_funda_wins a left join da.c_parms b
 on a.sic2 = b.sic2 and a.fyear = b.fyear
 /* at a minimum 10 obs (5 degrees of freedom) */
 and b._EDF_ > 5 ;
quit;

/* Means, medians for key variables and DA, ABSDA */
proc means data=da.d_model1 n mean median ;
var tac inv_at_l drevadj ppe roa DA ABSDA ;
run; 

/*	Output dataset  */
proc export data = da.d_model1  (keep = gvkey fyear datadate sich tac inv_at_l drevadj ppe roa DA ABSDA) 
outfile = "&projectDir.stata/from sas/absda.dta" replace; run;