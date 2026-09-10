# Переводит растровый эскиз в векторные контуры.
#
# Marching squares по бинарной маске даёт замкнутые контуры (внешние и дырки),
# дальше Дуглас–Пейкер убирает лишние точки, а Кэтмулл–Ром превращает
# ломаную в кубические кривые. На выходе — SVG-путь с fill-rule evenodd.

param(
  [string]$In        = 'C:\Users\PC\Pictures\ласт.png',
  [string]$Out       = 'C:\Users\PC\Desktop\ии\For Andrey\_traced.svg',
  [int]   $Threshold = 128,
  [double]$Epsilon   = 0.9,
  [double]$Smooth    = 0.55,
  [int]   $MinArea   = 12
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$code = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Text;

public class Tracer
{
    // ─── контур как список точек ───
    static double Dist(double px, double py, double ax, double ay, double bx, double by)
    {
        double dx = bx - ax, dy = by - ay;
        double len2 = dx * dx + dy * dy;
        if (len2 < 1e-12) { dx = px - ax; dy = py - ay; return Math.Sqrt(dx * dx + dy * dy); }
        double t = ((px - ax) * dx + (py - ay) * dy) / len2;
        t = Math.Max(0, Math.Min(1, t));
        double cx = ax + t * dx, cy = ay + t * dy;
        return Math.Sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
    }

    static void Simplify(List<double[]> pts, int first, int last, double eps, bool[] keep)
    {
        if (last <= first + 1) return;
        double maxD = -1; int idx = -1;
        for (int i = first + 1; i < last; i++)
        {
            double d = Dist(pts[i][0], pts[i][1], pts[first][0], pts[first][1], pts[last][0], pts[last][1]);
            if (d > maxD) { maxD = d; idx = i; }
        }
        if (maxD > eps)
        {
            keep[idx] = true;
            Simplify(pts, first, idx, eps, keep);
            Simplify(pts, idx, last, eps, keep);
        }
    }

    static List<double[]> Douglas(List<double[]> pts, double eps)
    {
        if (pts.Count < 3) return pts;
        bool[] keep = new bool[pts.Count];
        keep[0] = true; keep[pts.Count - 1] = true;
        Simplify(pts, 0, pts.Count - 1, eps, keep);
        var res = new List<double[]>();
        for (int i = 0; i < pts.Count; i++) if (keep[i]) res.Add(pts[i]);
        return res;
    }

    static double Area(List<double[]> p)
    {
        double a = 0;
        for (int i = 0; i < p.Count; i++)
        {
            int j = (i + 1) % p.Count;
            a += p[i][0] * p[j][1] - p[j][0] * p[i][1];
        }
        return a / 2.0;
    }

    public static string Run(string path, int threshold, double eps, double smooth, int minArea,
                             out int wOut, out int hOut, out int contourCount)
    {
        Bitmap bmp = new Bitmap(path);
        int w = bmp.Width, h = bmp.Height;
        wOut = w; hOut = h;

        // бинарная маска с рамкой в один пиксель, чтобы контуры замыкались
        bool[,] m = new bool[w + 2, h + 2];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                Color c = bmp.GetPixel(x, y);
                int lum = (c.R * 299 + c.G * 587 + c.B * 114) / 1000;
                m[x + 1, y + 1] = lum > threshold;
            }
        bmp.Dispose();

        int gw = w + 2, gh = h + 2;

        // ─── marching squares: собираем направленные отрезки ───
        var edges = new Dictionary<long, List<long>>();
        Func<double, double, long> key = (x, y) =>
            ((long)Math.Round(x * 2) << 20) ^ (long)Math.Round(y * 2);
        var coord = new Dictionary<long, double[]>();

        Action<double, double, double, double> add = (x1, y1, x2, y2) =>
        {
            long k1 = key(x1, y1), k2 = key(x2, y2);
            if (!coord.ContainsKey(k1)) coord[k1] = new double[] { x1, y1 };
            if (!coord.ContainsKey(k2)) coord[k2] = new double[] { x2, y2 };
            if (!edges.ContainsKey(k1)) edges[k1] = new List<long>();
            edges[k1].Add(k2);
        };

        for (int y = 0; y < gh - 1; y++)
            for (int x = 0; x < gw - 1; x++)
            {
                bool tl = m[x, y], tr = m[x + 1, y], br = m[x + 1, y + 1], bl = m[x, y + 1];
                int idx = (tl ? 8 : 0) | (tr ? 4 : 0) | (br ? 2 : 0) | (bl ? 1 : 0);
                double N_x = x + 0.5, N_y = y;
                double E_x = x + 1.0, E_y = y + 0.5;
                double S_x = x + 0.5, S_y = y + 1.0;
                double W_x = x, W_y = y + 0.5;

                switch (idx)
                {
                    case 1:  add(W_x, W_y, S_x, S_y); break;
                    case 2:  add(S_x, S_y, E_x, E_y); break;
                    case 3:  add(W_x, W_y, E_x, E_y); break;
                    case 4:  add(E_x, E_y, N_x, N_y); break;
                    case 5:  add(W_x, W_y, N_x, N_y); add(E_x, E_y, S_x, S_y); break;
                    case 6:  add(S_x, S_y, N_x, N_y); break;
                    case 7:  add(W_x, W_y, N_x, N_y); break;
                    case 8:  add(N_x, N_y, W_x, W_y); break;
                    case 9:  add(N_x, N_y, S_x, S_y); break;
                    case 10: add(N_x, N_y, E_x, E_y); add(S_x, S_y, W_x, W_y); break;
                    case 11: add(N_x, N_y, E_x, E_y); break;
                    case 12: add(E_x, E_y, W_x, W_y); break;
                    case 13: add(E_x, E_y, S_x, S_y); break;
                    case 14: add(S_x, S_y, W_x, W_y); break;
                }
            }

        // ─── сшиваем отрезки в замкнутые контуры ───
        var contours = new List<List<double[]>>();
        var used = new HashSet<string>();

        foreach (var start in new List<long>(edges.Keys))
        {
            foreach (var firstTo in edges[start])
            {
                string eid = start + ">" + firstTo;
                if (used.Contains(eid)) continue;

                var poly = new List<double[]>();
                long cur = start, next = firstTo;
                poly.Add(coord[cur]);

                while (true)
                {
                    used.Add(cur + ">" + next);
                    poly.Add(coord[next]);
                    if (next == start) break;
                    if (!edges.ContainsKey(next)) break;

                    long pick = -1;
                    foreach (var cand in edges[next])
                        if (!used.Contains(next + ">" + cand)) { pick = cand; break; }
                    if (pick < 0) break;
                    cur = next; next = pick;
                }

                if (poly.Count > 3) contours.Add(poly);
            }
        }

        // ─── упрощение и сглаживание ───
        var sb = new StringBuilder();
        var ci = CultureInfo.InvariantCulture;
        int kept = 0;

        foreach (var raw in contours)
        {
            if (Math.Abs(Area(raw)) < minArea) continue;
            var p = Douglas(raw, eps);
            if (p.Count < 4) continue;
            if (p.Count > 1 &&
                Math.Abs(p[0][0] - p[p.Count - 1][0]) < 1e-9 &&
                Math.Abs(p[0][1] - p[p.Count - 1][1]) < 1e-9)
                p.RemoveAt(p.Count - 1);
            if (p.Count < 4) continue;
            kept++;

            int n = p.Count;
            sb.Append("M").Append(p[0][0].ToString("0.##", ci)).Append(" ").Append(p[0][1].ToString("0.##", ci));
            for (int i = 0; i < n; i++)
            {
                double[] p0 = p[(i - 1 + n) % n], p1 = p[i], p2 = p[(i + 1) % n], p3 = p[(i + 2) % n];
                double c1x = p1[0] + (p2[0] - p0[0]) * smooth / 3.0;
                double c1y = p1[1] + (p2[1] - p0[1]) * smooth / 3.0;
                double c2x = p2[0] - (p3[0] - p1[0]) * smooth / 3.0;
                double c2y = p2[1] - (p3[1] - p1[1]) * smooth / 3.0;
                sb.Append("C").Append(c1x.ToString("0.##", ci)).Append(" ").Append(c1y.ToString("0.##", ci))
                  .Append(" ").Append(c2x.ToString("0.##", ci)).Append(" ").Append(c2y.ToString("0.##", ci))
                  .Append(" ").Append(p2[0].ToString("0.##", ci)).Append(" ").Append(p2[1].ToString("0.##", ci));
            }
            sb.Append("Z");
        }

        contourCount = kept;
        return sb.ToString();
    }
}
'@

Add-Type -TypeDefinition $code -ReferencedAssemblies System.Drawing, System.Drawing.Primitives -ErrorAction Stop

$w = 0; $h = 0; $n = 0
$d = [Tracer]::Run($In, $Threshold, $Epsilon, $Smooth, $MinArea, [ref]$w, [ref]$h, [ref]$n)

$svg = @"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $($w + 2) $($h + 2)">
  <path fill="currentColor" fill-rule="evenodd" d="$d"/>
</svg>
"@

[System.IO.File]::WriteAllText($Out, $svg, (New-Object System.Text.UTF8Encoding $false))
"контуров: {0}, размер сетки: {1}x{2}, файл: {3} КБ" -f $n, ($w + 2), ($h + 2), [math]::Round((Get-Item $Out).Length / 1KB, 1)
