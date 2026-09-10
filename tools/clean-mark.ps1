# Чистит обведённый эскиз: обод становится математически точным кольцом.
#
# Притягивание точек к радиусу (align-circles.ps1) убирает крупные отклонения,
# но между точками остаются волны и вмятины. Здесь участки контура, лежащие
# на ободе, заменяются настоящими дугами окружности — командой A. После этого
# у обода нет ни одной неровности, а крыло, клюв и хвост остаются как нарисованы.

param(
  [string]$In        = 'C:\Users\PC\Pictures\ласт.png',
  [string]$Out       = 'C:\Users\PC\Desktop\ии\For Andrey\_clean.svg',
  [int]   $Threshold = 128,
  [int]   $Upscale   = 4,
  [double]$Epsilon   = 3.0,   # в пикселях увеличенного растра
  [double]$Smooth    = 0.6,
  [double]$ArcTol    = 6.0,   # допуск «точка лежит на ободе», в пикселях увеличенного растра
  [int]   $ArcMinPts = 4      # короче — не дуга, а случайное совпадение
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$code = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Text;

public class Cleaner
{
    static CultureInfo CI = CultureInfo.InvariantCulture;

    static double PDist(double px,double py,double ax,double ay,double bx,double by){
        double dx=bx-ax, dy=by-ay, l2=dx*dx+dy*dy;
        if(l2<1e-12){dx=px-ax;dy=py-ay;return Math.Sqrt(dx*dx+dy*dy);}
        double t=((px-ax)*dx+(py-ay)*dy)/l2; t=Math.Max(0,Math.Min(1,t));
        double qx=ax+t*dx, qy=ay+t*dy;
        return Math.Sqrt((px-qx)*(px-qx)+(py-qy)*(py-qy));
    }
    static void Simp(List<double[]> p,int f,int l,double e,bool[] k){
        if(l<=f+1)return; double md=-1; int id=-1;
        for(int i=f+1;i<l;i++){double d=PDist(p[i][0],p[i][1],p[f][0],p[f][1],p[l][0],p[l][1]); if(d>md){md=d;id=i;}}
        if(md>e){k[id]=true;Simp(p,f,id,e,k);Simp(p,id,l,e,k);}
    }
    static List<double[]> Doug(List<double[]> p,double e){
        if(p.Count<3)return p;
        bool[] k=new bool[p.Count]; k[0]=true; k[p.Count-1]=true;
        Simp(p,0,p.Count-1,e,k);
        var r=new List<double[]>(); for(int i=0;i<p.Count;i++) if(k[i]) r.Add(p[i]); return r;
    }
    static double Area(List<double[]> p){
        double a=0; for(int i=0;i<p.Count;i++){int j=(i+1)%p.Count; a+=p[i][0]*p[j][1]-p[j][0]*p[i][1];} return a/2.0;
    }
    static double[] Fit(List<double[]> pts){
        double Sx=0,Sy=0,Sxx=0,Syy=0,Sxy=0,Sxz=0,Syz=0,Sz=0; int n=pts.Count;
        foreach(var p in pts){ double x=p[0],y=p[1],z=x*x+y*y;
            Sx+=x;Sy+=y;Sxx+=x*x;Syy+=y*y;Sxy+=x*y;Sxz+=x*z;Syz+=y*z;Sz+=z; }
        double[,] a={{Sxx,Sxy,Sx},{Sxy,Syy,Sy},{Sx,Sy,n}};
        double[] b={-Sxz,-Syz,-Sz};
        for(int i=0;i<3;i++){
            int piv=i;
            for(int k=i+1;k<3;k++) if(Math.Abs(a[k,i])>Math.Abs(a[piv,i])) piv=k;
            if(piv!=i){ for(int j=0;j<3;j++){double t=a[i,j];a[i,j]=a[piv,j];a[piv,j]=t;} double t2=b[i];b[i]=b[piv];b[piv]=t2; }
            for(int k=i+1;k<3;k++){ double f=a[k,i]/a[i,i];
                for(int j=i;j<3;j++) a[k,j]-=f*a[i,j]; b[k]-=f*b[i]; }
        }
        double[] s=new double[3];
        for(int i=2;i>=0;i--){ double v=b[i]; for(int j=i+1;j<3;j++) v-=a[i,j]*s[j]; s[i]=v/a[i,i]; }
        double cx=-s[0]/2, cy=-s[1]/2;
        return new double[]{cx,cy,Math.Sqrt(cx*cx+cy*cy-s[2])};
    }

    public static string Run(string path,int th,int up,double eps,double smooth,
                             double arcTol,int arcMinPts,
                             out int W,out int H,out string info)
    {
        Bitmap src=new Bitmap(path), bmp;
        if(up>1){
            bmp=new Bitmap(src.Width*up, src.Height*up);
            using(Graphics g=Graphics.FromImage(bmp)){
                g.InterpolationMode=System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.HighQuality;
                g.PixelOffsetMode=System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
                g.DrawImage(src,new Rectangle(0,0,bmp.Width,bmp.Height),0,0,src.Width,src.Height,GraphicsUnit.Pixel);
            }
            src.Dispose();
        } else bmp=src;
        int w=bmp.Width, h=bmp.Height; W=w; H=h;

        bool[,] m=new bool[w+2,h+2];
        for(int y=0;y<h;y++) for(int x=0;x<w;x++){
            Color c=bmp.GetPixel(x,y);
            m[x+1,y+1]=((c.R*299+c.G*587+c.B*114)/1000)>th;
        }
        bmp.Dispose();

        // ─── контуры (marching squares) ───
        var edges=new Dictionary<long,List<long>>();
        var coord=new Dictionary<long,double[]>();
        Func<double,double,long> key=(x,y)=>((long)Math.Round(x*2)<<20)^(long)Math.Round(y*2);
        Action<double,double,double,double> add=(x1,y1,x2,y2)=>{
            long k1=key(x1,y1),k2=key(x2,y2);
            if(!coord.ContainsKey(k1))coord[k1]=new double[]{x1,y1};
            if(!coord.ContainsKey(k2))coord[k2]=new double[]{x2,y2};
            if(!edges.ContainsKey(k1))edges[k1]=new List<long>();
            edges[k1].Add(k2);
        };
        for(int y=0;y<h+1;y++) for(int x=0;x<w+1;x++){
            bool tl=m[x,y],tr=m[x+1,y],br=m[x+1,y+1],bl=m[x,y+1];
            int idx=(tl?8:0)|(tr?4:0)|(br?2:0)|(bl?1:0);
            double Nx=x+0.5,Ny=y, Ex=x+1.0,Ey=y+0.5, Sx=x+0.5,Sy=y+1.0, Wx=x,Wy=y+0.5;
            switch(idx){
                case 1: add(Wx,Wy,Sx,Sy); break;   case 2: add(Sx,Sy,Ex,Ey); break;
                case 3: add(Wx,Wy,Ex,Ey); break;   case 4: add(Ex,Ey,Nx,Ny); break;
                case 5: add(Wx,Wy,Nx,Ny); add(Ex,Ey,Sx,Sy); break;
                case 6: add(Sx,Sy,Nx,Ny); break;   case 7: add(Wx,Wy,Nx,Ny); break;
                case 8: add(Nx,Ny,Wx,Wy); break;   case 9: add(Nx,Ny,Sx,Sy); break;
                case 10: add(Nx,Ny,Ex,Ey); add(Sx,Sy,Wx,Wy); break;
                case 11: add(Nx,Ny,Ex,Ey); break;  case 12: add(Ex,Ey,Wx,Wy); break;
                case 13: add(Ex,Ey,Sx,Sy); break;  case 14: add(Sx,Sy,Wx,Wy); break;
            }
        }
        var contours=new List<List<double[]>>();
        var used=new HashSet<string>();
        foreach(var st in new List<long>(edges.Keys))
            foreach(var ft in edges[st]){
                if(used.Contains(st+">"+ft))continue;
                var poly=new List<double[]>(); long cur=st,next=ft; poly.Add(coord[cur]);
                while(true){
                    used.Add(cur+">"+next); poly.Add(coord[next]);
                    if(next==st)break;
                    if(!edges.ContainsKey(next))break;
                    long pick=-1;
                    foreach(var cd in edges[next]) if(!used.Contains(next+">"+cd)){pick=cd;break;}
                    if(pick<0)break;
                    cur=next; next=pick;
                }
                if(poly.Count>3)contours.Add(poly);
            }

        // ─── центр колеса по внешней границе ───
        var outer=new List<double[]>();
        for(int y=0;y<h;y++) for(int x=0;x<w;x++) if(m[x+1,y+1]){ if(x<w*0.42) outer.Add(new double[]{x+1,y+1}); break; }
        for(int x=0;x<w;x++) for(int y=h-1;y>=0;y--) if(m[x+1,y+1]){ if(y>h*0.55) outer.Add(new double[]{x+1,y+1}); break; }
        var fit=Fit(outer);
        double CX=fit[0], CY=fit[1];

        // ─── радиусы обода: лучи в секторе, где кроме обода ничего нет ───
        var rIn=new List<double>(); var rOut=new List<double>(); var thick2=new List<double>();
        for(double ang=95;ang<=175;ang+=2.5){
            double a=ang*Math.PI/180, ca=Math.Cos(a), sa=Math.Sin(a);
            double lastWhiteStart=-1, lastWhiteEnd=-1, curStart=-1;
            bool prev=false;
            for(double r=6;r<w*1.5;r+=0.5){
                int px=(int)Math.Round(CX+ca*r), py=(int)Math.Round(CY+sa*r);
                bool val = (px>=0&&px<w+2&&py>=0&&py<h+2) && m[px,py];
                if(val && !prev) curStart=r;
                if(!val && prev){ lastWhiteStart=curStart; lastWhiteEnd=r; }
                prev=val;
            }
            if(lastWhiteStart>0 && lastWhiteEnd-lastWhiteStart>4){
                rIn.Add(lastWhiteStart); rOut.Add(lastWhiteEnd);
                thick2.Add(lastWhiteEnd-lastWhiteStart);   // толщина именно этого луча
            }
        }
        rOut.Sort();
        double ROUT= rOut.Count>0 ? rOut[rOut.Count/2] : 0;

        // Толщина обода — по самым «чистым» лучам. Медиана завышает: часть лучей
        // проходит через спицу, слитую с ободом, и меряет их заодно с ним.
        thick2.Sort();
        double thick = thick2.Count>0 ? thick2[Math.Max(0,(int)(thick2.Count*0.15))] : 0;
        double RIN = ROUT - thick;

        // ─── сборка пути: дуги обода заменяем командой A ───
        var sb=new StringBuilder(); int kept=0, arcs=0;
        double minArea = 40.0*up*up;

        foreach(var raw in contours){
            if(Math.Abs(Area(raw))<minArea) continue;
            var p=Doug(raw,eps);
            if(p.Count>1 && Math.Abs(p[0][0]-p[p.Count-1][0])<1e-9 && Math.Abs(p[0][1]-p[p.Count-1][1])<1e-9)
                p.RemoveAt(p.Count-1);
            int n=p.Count;
            if(n<4) continue;
            kept++;

            // метка радиуса для каждой точки: 0 — не на ободе, 1 — внутренний, 2 — внешний
            int[] lab=new int[n];
            for(int i=0;i<n;i++){
                double d=Math.Sqrt((p[i][0]-CX)*(p[i][0]-CX)+(p[i][1]-CY)*(p[i][1]-CY));
                if(ROUT>0 && Math.Abs(d-ROUT)<arcTol) lab[i]=2;
                else if(RIN>0 && Math.Abs(d-RIN)<arcTol) lab[i]=1;
            }
            // точки на ободе кладём точно на окружность
            for(int i=0;i<n;i++){
                if(lab[i]==0) continue;
                double R = lab[i]==2?ROUT:RIN;
                double dx=p[i][0]-CX, dy=p[i][1]-CY, d=Math.Sqrt(dx*dx+dy*dy);
                if(d>1e-6){ p[i][0]=CX+dx/d*R; p[i][1]=CY+dy/d*R; }
            }

            sb.Append("M").Append(p[0][0].ToString("0.##",CI)).Append(" ").Append(p[0][1].ToString("0.##",CI));
            int i2=0;
            while(i2<n){
                int cur=(i2+1)%n;
                if(lab[i2]!=0 && lab[i2]==lab[cur]){
                    // считаем, сколько подряд точек лежит на этой же окружности
                    // не даём группе перескочить через конец контура —
                    // иначе дуга замкнётся не туда и срежет часть рисунка
                    int len=1, j=i2;
                    while(j+1<n && lab[j+1]==lab[i2]){ j++; len++; }
                    if(len>=arcMinPts){
                        double R=lab[i2]==2?ROUT:RIN;
                        int endIdx=j%n;
                        double a1=Math.Atan2(p[i2][1]-CY,p[i2][0]-CX);
                        double a2=Math.Atan2(p[endIdx][1]-CY,p[endIdx][0]-CX);
                        double da=a2-a1;
                        while(da<=-Math.PI) da+=2*Math.PI;
                        while(da>Math.PI) da-=2*Math.PI;
                        int sweep = da>0?1:0;
                        int large = Math.Abs(da)>Math.PI?1:0;
                        sb.Append("A").Append(R.ToString("0.##",CI)).Append(" ").Append(R.ToString("0.##",CI))
                          .Append(" 0 ").Append(large).Append(" ").Append(sweep).Append(" ")
                          .Append(p[endIdx][0].ToString("0.##",CI)).Append(" ").Append(p[endIdx][1].ToString("0.##",CI));
                        arcs++;
                        i2=j;
                        continue;
                    }
                }
                // обычный участок — гладкая кривая
                double[] q0=p[(i2-1+n)%n],q1=p[i2%n],q2=p[(i2+1)%n],q3=p[(i2+2)%n];
                double c1x=q1[0]+(q2[0]-q0[0])*smooth/3.0, c1y=q1[1]+(q2[1]-q0[1])*smooth/3.0;
                double c2x=q2[0]-(q3[0]-q1[0])*smooth/3.0, c2y=q2[1]-(q3[1]-q1[1])*smooth/3.0;
                sb.Append("C").Append(c1x.ToString("0.##",CI)).Append(" ").Append(c1y.ToString("0.##",CI))
                  .Append(" ").Append(c2x.ToString("0.##",CI)).Append(" ").Append(c2y.ToString("0.##",CI))
                  .Append(" ").Append(q2[0].ToString("0.##",CI)).Append(" ").Append(q2[1].ToString("0.##",CI));
                i2++;
            }
            sb.Append("Z");
        }

        info=string.Format(CI,"центр ({0:0.0}, {1:0.0}); обод {2:0.0}…{3:0.0} (толщина {4:0.0}); дуг: {5}; контуров: {6}",
                           CX,CY,RIN,ROUT,ROUT-RIN,arcs,kept);
        return sb.ToString();
    }
}
'@

Add-Type -TypeDefinition $code -ReferencedAssemblies System.Drawing, System.Drawing.Primitives -ErrorAction Stop

$W = 0; $H = 0; $info = ''
$d = [Cleaner]::Run($In, $Threshold, $Upscale, $Epsilon, $Smooth,
                    $ArcTol, $ArcMinPts, [ref]$W, [ref]$H, [ref]$info)

$svg = @"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $W $H" color="#f2f0ec">
  <path fill="currentColor" fill-rule="evenodd" d="$d"/>
</svg>
"@
[System.IO.File]::WriteAllText($Out, $svg, (New-Object System.Text.UTF8Encoding $false))
$info
"файл: {0} КБ" -f [math]::Round((Get-Item $Out).Length / 1KB, 1)
