# Выравнивает окружности на обведённом эскизе.
#
# Дуга обода нарисована от руки: подгонка показала отклонение до 1,5 px.
# Скрипт находит центр колеса и радиусы (по гистограмме расстояний от центра
# до точек контура), после чего притягивает к этим радиусам все точки,
# которые лежат рядом. Остальной рисунок остаётся как есть.

param(
  [string]$In        = 'C:\Users\PC\Pictures\ласт.png',
  [string]$Out       = 'C:\Users\PC\Desktop\ии\For Andrey\_aligned.svg',
  [int]   $Threshold = 128,
  [double]$Epsilon   = 0.8,
  [double]$Smooth    = 0.6,
  [double]$Snap      = 2.2,   # насколько близко точка должна лежать к радиусу
  [int]   $MinArea   = 12,
  [int]   $Upscale   = 4,     # эскиз 111 px — увеличиваем, иначе контуры ступенчатые
  [int]   $TopRadii  = 2      # выравниваем только обод: внешний и внутренний край
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$code = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Text;

public class Aligner
{
    public static double CX, CY;
    public static List<double> Radii = new List<double>();

    static double D(double px,double py,double ax,double ay,double bx,double by){
        double dx=bx-ax, dy=by-ay, l2=dx*dx+dy*dy;
        if(l2<1e-12){dx=px-ax;dy=py-ay;return Math.Sqrt(dx*dx+dy*dy);}
        double t=((px-ax)*dx+(py-ay)*dy)/l2; t=Math.Max(0,Math.Min(1,t));
        double cx=ax+t*dx, cy=ay+t*dy;
        return Math.Sqrt((px-cx)*(px-cx)+(py-cy)*(py-cy));
    }
    static void Simp(List<double[]> p,int f,int l,double e,bool[] k){
        if(l<=f+1)return; double md=-1; int id=-1;
        for(int i=f+1;i<l;i++){double d=D(p[i][0],p[i][1],p[f][0],p[f][1],p[l][0],p[l][1]); if(d>md){md=d;id=i;}}
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

    // подгонка окружности методом Касы
    static double[] Fit(List<double[]> pts){
        double Sx=0,Sy=0,Sxx=0,Syy=0,Sxy=0,Sxz=0,Syz=0,Sz=0; int n=pts.Count;
        foreach(var p in pts){
            double x=p[0],y=p[1],z=x*x+y*y;
            Sx+=x;Sy+=y;Sxx+=x*x;Syy+=y*y;Sxy+=x*y;Sxz+=x*z;Syz+=y*z;Sz+=z;
        }
        double[,] a={{Sxx,Sxy,Sx},{Sxy,Syy,Sy},{Sx,Sy,n}};
        double[] b={-Sxz,-Syz,-Sz};
        for(int i=0;i<3;i++){
            int piv=i;
            for(int k=i+1;k<3;k++) if(Math.Abs(a[k,i])>Math.Abs(a[piv,i])) piv=k;
            if(piv!=i){ for(int j=0;j<3;j++){double t=a[i,j];a[i,j]=a[piv,j];a[piv,j]=t;} double t2=b[i];b[i]=b[piv];b[piv]=t2; }
            for(int k=i+1;k<3;k++){
                double f=a[k,i]/a[i,i];
                for(int j=i;j<3;j++) a[k,j]-=f*a[i,j];
                b[k]-=f*b[i];
            }
        }
        double[] s=new double[3];
        for(int i=2;i>=0;i--){ double v=b[i]; for(int j=i+1;j<3;j++) v-=a[i,j]*s[j]; s[i]=v/a[i,i]; }
        double cx=-s[0]/2, cy=-s[1]/2;
        return new double[]{cx,cy,Math.Sqrt(cx*cx+cy*cy-s[2])};
    }

    public static string Run(string path,int th,double eps,double smooth,double snap,int minArea,
                             int upscale,int topRadii,
                             out int w,out int h,out string info)
    {
        Bitmap src=new Bitmap(path);
        Bitmap bmp;
        if(upscale>1){
            // сглаженное увеличение: убирает пиксельную лесенку до обводки
            bmp=new Bitmap(src.Width*upscale, src.Height*upscale);
            using(Graphics g=Graphics.FromImage(bmp)){
                g.InterpolationMode=System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.HighQuality;
                g.PixelOffsetMode=System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
                g.DrawImage(src,new Rectangle(0,0,bmp.Width,bmp.Height),
                            0,0,src.Width,src.Height,GraphicsUnit.Pixel);
            }
            src.Dispose();
        } else bmp=src;
        w=bmp.Width; h=bmp.Height;
        bool[,] m=new bool[w+2,h+2];
        for(int y=0;y<h;y++) for(int x=0;x<w;x++){
            Color c=bmp.GetPixel(x,y);
            m[x+1,y+1]=((c.R*299+c.G*587+c.B*114)/1000)>th;
        }
        bmp.Dispose();
        int gw=w+2, gh=h+2;

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
        for(int y=0;y<gh-1;y++) for(int x=0;x<gw-1;x++){
            bool tl=m[x,y],tr=m[x+1,y],br=m[x+1,y+1],bl=m[x,y+1];
            int idx=(tl?8:0)|(tr?4:0)|(br?2:0)|(bl?1:0);
            double Nx=x+0.5,Ny=y, Ex=x+1.0,Ey=y+0.5, Sx2=x+0.5,Sy2=y+1.0, Wx=x,Wy=y+0.5;
            switch(idx){
                case 1: add(Wx,Wy,Sx2,Sy2); break;
                case 2: add(Sx2,Sy2,Ex,Ey); break;
                case 3: add(Wx,Wy,Ex,Ey); break;
                case 4: add(Ex,Ey,Nx,Ny); break;
                case 5: add(Wx,Wy,Nx,Ny); add(Ex,Ey,Sx2,Sy2); break;
                case 6: add(Sx2,Sy2,Nx,Ny); break;
                case 7: add(Wx,Wy,Nx,Ny); break;
                case 8: add(Nx,Ny,Wx,Wy); break;
                case 9: add(Nx,Ny,Sx2,Sy2); break;
                case 10: add(Nx,Ny,Ex,Ey); add(Sx2,Sy2,Wx,Wy); break;
                case 11: add(Nx,Ny,Ex,Ey); break;
                case 12: add(Ex,Ey,Wx,Wy); break;
                case 13: add(Ex,Ey,Sx2,Sy2); break;
                case 14: add(Sx2,Sy2,Wx,Wy); break;
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

        // ─── центр колеса: по внешней границе слева и снизу ───
        var outer=new List<double[]>();
        for(int y=0;y<h;y++) for(int x=0;x<w;x++) if(m[x+1,y+1]){ if(x<w*0.42) outer.Add(new double[]{x,y}); break; }
        for(int x=0;x<w;x++) for(int y=h-1;y>=0;y--) if(m[x+1,y+1]){ if(y>h*0.55) outer.Add(new double[]{x,y}); break; }
        var fit=Fit(outer);
        CX=fit[0]+1; CY=fit[1]+1;   // +1 — поправка на рамку маски

        // ─── радиусы: пики гистограммы расстояний ───
        var hist=new int[400];
        foreach(var c in contours) foreach(var p in c){
            double d=Math.Sqrt((p[0]-CX)*(p[0]-CX)+(p[1]-CY)*(p[1]-CY));
            int b=(int)Math.Round(d);
            if(b>=8 && b<400) hist[b]++;
        }
        // Кандидаты — локальные пики; берём только самые «населённые»:
        // это обод. Остальные пики дают крыло и хвост, их трогать нельзя.
        var cand=new List<int[]>();
        for(int i=8;i<398;i++){
            bool peak = hist[i]>=hist[i-1] && hist[i]>=hist[i+1] && hist[i]>=hist[i-2] && hist[i]>=hist[i+2];
            if(peak && hist[i]>0) cand.Add(new int[]{i,hist[i]});
        }
        cand.Sort(delegate(int[] a,int[] b){ return b[1].CompareTo(a[1]); });
        foreach(var c in cand){
            if(Radii.Count>=topRadii) break;
            bool near=false;
            foreach(var r in Radii) if(Math.Abs(r-c[0])<snap*3) near=true;
            if(!near) Radii.Add(c[0]);
        }
        // уточняем каждый радиус средним по попавшим точкам
        for(int k=0;k<Radii.Count;k++){
            double sum=0; int n=0;
            foreach(var c in contours) foreach(var p in c){
                double d=Math.Sqrt((p[0]-CX)*(p[0]-CX)+(p[1]-CY)*(p[1]-CY));
                if(Math.Abs(d-Radii[k])<snap){ sum+=d; n++; }
            }
            if(n>0) Radii[k]=sum/n;
        }

        // ─── притягиваем точки к радиусам ───
        int snapped=0;
        foreach(var c in contours)
            foreach(var p in c){
                double dx=p[0]-CX, dy=p[1]-CY;
                double d=Math.Sqrt(dx*dx+dy*dy);
                foreach(var r in Radii)
                    if(Math.Abs(d-r)<snap && d>1e-6){
                        p[0]=CX+dx/d*r; p[1]=CY+dy/d*r; snapped++;
                        break;
                    }
            }

        var sb=new StringBuilder(); var ci=CultureInfo.InvariantCulture; int kept=0;
        foreach(var raw in contours){
            if(Math.Abs(Area(raw))<minArea) continue;
            var p=Doug(raw,eps);
            if(p.Count>1 && Math.Abs(p[0][0]-p[p.Count-1][0])<1e-9 && Math.Abs(p[0][1]-p[p.Count-1][1])<1e-9)
                p.RemoveAt(p.Count-1);
            if(p.Count<4) continue;
            kept++;
            int n=p.Count;
            sb.Append("M").Append(p[0][0].ToString("0.##",ci)).Append(" ").Append(p[0][1].ToString("0.##",ci));
            for(int i=0;i<n;i++){
                double[] p0=p[(i-1+n)%n],p1=p[i],p2=p[(i+1)%n],p3=p[(i+2)%n];
                double c1x=p1[0]+(p2[0]-p0[0])*smooth/3.0, c1y=p1[1]+(p2[1]-p0[1])*smooth/3.0;
                double c2x=p2[0]-(p3[0]-p1[0])*smooth/3.0, c2y=p2[1]-(p3[1]-p1[1])*smooth/3.0;
                sb.Append("C").Append(c1x.ToString("0.##",ci)).Append(" ").Append(c1y.ToString("0.##",ci))
                  .Append(" ").Append(c2x.ToString("0.##",ci)).Append(" ").Append(c2y.ToString("0.##",ci))
                  .Append(" ").Append(p2[0].ToString("0.##",ci)).Append(" ").Append(p2[1].ToString("0.##",ci));
            }
            sb.Append("Z");
        }

        var rs=new StringBuilder();
        foreach(var r in Radii) rs.Append(r.ToString("0.0",ci)).Append(" ");
        info=string.Format(ci,"центр ({0:0.0}, {1:0.0}); радиусы: {2}; притянуто точек: {3}; контуров: {4}",
                           CX,CY,rs.ToString().Trim(),snapped,kept);
        return sb.ToString();
    }
}
'@

Add-Type -TypeDefinition $code -ReferencedAssemblies System.Drawing, System.Drawing.Primitives -ErrorAction Stop

$w = 0; $h = 0; $info = ''
$d = [Aligner]::Run($In, $Threshold, $Epsilon * $Upscale, $Smooth, $Snap * $Upscale,
                    $MinArea * $Upscale * $Upscale, $Upscale, $TopRadii,
                    [ref]$w, [ref]$h, [ref]$info)

$svg = @"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $($w + 2) $($h + 2)">
  <path fill="currentColor" fill-rule="evenodd" d="$d"/>
</svg>
"@
[System.IO.File]::WriteAllText($Out, $svg, (New-Object System.Text.UTF8Encoding $false))
$info
"файл: {0} КБ" -f [math]::Round((Get-Item $Out).Length / 1KB, 1)
