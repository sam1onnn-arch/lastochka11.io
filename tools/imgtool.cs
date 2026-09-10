using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;

public static class ImgTool
{
    public static int[] Load(string path, out int w, out int h)
    {
        using (var src = new Bitmap(path))
        {
            w = src.Width; h = src.Height;
            using (var bm = new Bitmap(w, h, PixelFormat.Format32bppArgb))
            {
                using (var g = Graphics.FromImage(bm)) { g.DrawImage(src, new Rectangle(0, 0, w, h)); }
                var d = bm.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                int[] px = new int[w * h];
                Marshal.Copy(d.Scan0, px, 0, w * h);
                bm.UnlockBits(d);
                return px;
            }
        }
    }

    public static void SavePx(int[] px, int w, int h, string path, bool png)
    {
        using (var bm = new Bitmap(w, h, PixelFormat.Format32bppArgb))
        {
            var d = bm.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            Marshal.Copy(px, 0, d.Scan0, w * h);
            bm.UnlockBits(d);
            SaveBitmap(bm, path, png);
        }
    }

    public static void SaveBitmap(Bitmap bm, string path, bool png)
    {
        if (png) { bm.Save(path, ImageFormat.Png); return; }
        using (var flat = new Bitmap(bm.Width, bm.Height, PixelFormat.Format24bppRgb))
        {
            using (var g = Graphics.FromImage(flat)) { g.Clear(Color.Black); g.DrawImage(bm, 0, 0); }
            var enc = GetEncoder(ImageFormat.Jpeg);
            var ps = new EncoderParameters(1);
            ps.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 95L);
            flat.Save(path, enc, ps);
        }
    }

    static ImageCodecInfo GetEncoder(ImageFormat f)
    {
        foreach (var c in ImageCodecInfo.GetImageEncoders()) if (c.FormatID == f.Guid) return c;
        return null;
    }

    public static int Lum(int p)
    {
        int r = (p >> 16) & 255, g = (p >> 8) & 255, b = p & 255;
        return (299 * r + 587 * g + 114 * b) / 1000;
    }

    // ---------------- connected components ----------------
    class Comp { public int Id, Count, MinX, MinY, MaxX, MaxY; }

    static List<Comp> Label(int[] px, int w, int h, int thr, out int[] label)
    {
        bool[] mask = new bool[w * h];
        for (int i = 0; i < px.Length; i++) mask[i] = Lum(px[i]) > thr;
        label = new int[w * h];
        var res = new List<Comp>();
        var st = new Stack<int>();
        int cur = 0;
        for (int i = 0; i < w * h; i++)
        {
            if (!mask[i] || label[i] != 0) continue;
            cur++; st.Push(i); label[i] = cur;
            var c = new Comp { Id = cur, MinX = w, MinY = h, MaxX = -1, MaxY = -1 };
            while (st.Count > 0)
            {
                int q = st.Pop(); c.Count++;
                int qx = q % w, qy = q / w;
                if (qx < c.MinX) c.MinX = qx; if (qx > c.MaxX) c.MaxX = qx;
                if (qy < c.MinY) c.MinY = qy; if (qy > c.MaxY) c.MaxY = qy;
                for (int dy = -1; dy <= 1; dy++)
                    for (int dx = -1; dx <= 1; dx++)
                    {
                        int nx = qx + dx, ny = qy + dy;
                        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
                        int n = ny * w + nx;
                        if (mask[n] && label[n] == 0) { label[n] = cur; st.Push(n); }
                    }
            }
            res.Add(c);
        }
        res.Sort((a, b) => b.Count.CompareTo(a.Count));
        return res;
    }

    public static string AnalyzeLogo(string path, int thr)
    {
        int w, h; var px = Load(path, out w, out h);
        int[] lab;
        var res = Label(px, w, h, thr, out lab);
        var sb = new StringBuilder();
        sb.AppendLine("logo " + w + "x" + h + " thr=" + thr + " components=" + res.Count);
        for (int i = 0; i < Math.Min(6, res.Count); i++)
        {
            var r = res[i];
            sb.AppendLine(string.Format("  rank{0} id={1} px={2} bbox=({3},{4})-({5},{6}) {7}x{8}",
                i, r.Id, r.Count, r.MinX, r.MinY, r.MaxX, r.MaxY, r.MaxX - r.MinX + 1, r.MaxY - r.MinY + 1));
        }
        return sb.ToString();
    }

    // ---------------- rim detection ----------------
    static bool Band(int[] px, int w, int h, double cx, double cy, double ang, int rmin, int rmax, int thr, int minRun, out int ri, out int ro)
    {
        ri = ro = -1;
        double ca = Math.Cos(ang), sa = Math.Sin(ang);
        int runStart = -1;
        for (int r = rmin; r <= rmax; r++)
        {
            int xi = (int)Math.Round(cx + ca * r), yi = (int)Math.Round(cy + sa * r);
            bool bright = false;
            if (xi >= 0 && yi >= 0 && xi < w && yi < h) bright = Lum(px[yi * w + xi]) > thr;
            if (bright) { if (runStart < 0) runStart = r; }
            else
            {
                if (runStart >= 0)
                {
                    if (r - runStart >= minRun) { ri = runStart; ro = r - 1; return true; }
                    runStart = -1;
                }
            }
        }
        if (runStart >= 0 && rmax - runStart >= minRun) { ri = runStart; ro = rmax; return true; }
        return false;
    }

    public static string FindRim(string path, int cx0, int cy0, int span, int rmin, int rmax, int thr, int minRun)
    {
        int w, h; var px = Load(path, out w, out h);
        int bestCx = cx0, bestCy = cy0, bestIn = -1;
        double bestSpread = 1e9, bestMed = 0;
        int nAng = 90;
        for (int cy = cy0 - span; cy <= cy0 + span; cy += 2)
            for (int cx = cx0 - span; cx <= cx0 + span; cx += 2)
            {
                var vals = new List<double>();
                for (int a = 0; a < nAng; a++)
                {
                    double ang = a * 2.0 * Math.PI / nAng;
                    int ri, ro;
                    if (Band(px, w, h, cx, cy, ang, rmin, rmax, thr, minRun, out ri, out ro)) vals.Add(ro);
                }
                if (vals.Count < 20) continue;
                vals.Sort();
                double med = vals[vals.Count / 2];
                int inl = 0; double sp = 0;
                foreach (var v in vals) if (Math.Abs(v - med) <= 6) { inl++; sp += Math.Abs(v - med); }
                double avg = sp / Math.Max(1, inl);
                if (inl > bestIn || (inl == bestIn && avg < bestSpread))
                { bestIn = inl; bestSpread = avg; bestCx = cx; bestCy = cy; bestMed = med; }
            }
        var ins = new List<double>(); var outs = new List<double>();
        var sb = new StringBuilder();
        sb.AppendLine(string.Format("image {0}x{1}  best center=({2},{3}) inliers={4}/{5} medOuter={6}", w, h, bestCx, bestCy, bestIn, nAng, bestMed));
        for (int a = 0; a < nAng; a++)
        {
            double ang = a * 2.0 * Math.PI / nAng;
            int ri, ro;
            if (Band(px, w, h, bestCx, bestCy, ang, rmin, rmax, thr, minRun, out ri, out ro))
                if (Math.Abs(ro - bestMed) <= 8) { ins.Add(ri); outs.Add(ro); }
        }
        ins.Sort(); outs.Sort();
        sb.AppendLine(string.Format("rim inner median={0} outer median={1} n={2}",
            ins.Count > 0 ? ins[ins.Count / 2] : -1, outs.Count > 0 ? outs[outs.Count / 2] : -1, ins.Count));
        return sb.ToString();
    }

    public static void DebugCircles(string path, string outPath, int cx, int cy, int[] radii)
    {
        using (var src = new Bitmap(path))
        using (var bm = new Bitmap(src.Width, src.Height, PixelFormat.Format32bppArgb))
        {
            using (var g = Graphics.FromImage(bm))
            {
                g.DrawImage(src, 0, 0, src.Width, src.Height);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                var cols = new Color[] { Color.Red, Color.Lime, Color.Cyan, Color.Magenta };
                for (int i = 0; i < radii.Length; i++)
                {
                    using (var pen = new Pen(cols[i % cols.Length], 2f))
                        g.DrawEllipse(pen, cx - radii[i], cy - radii[i], radii[i] * 2, radii[i] * 2);
                }
                using (var pen = new Pen(Color.Yellow, 2f))
                {
                    g.DrawLine(pen, cx - 12, cy, cx + 12, cy);
                    g.DrawLine(pen, cx, cy - 12, cx, cy + 12);
                }
            }
            SaveBitmap(bm, outPath, false);
        }
    }

    // ---------------- logo extraction ----------------
    // mode 0 = bird only (largest component), 1 = bird + ring (two largest)
    public static Bitmap BuildLogo(string path, int thr, int mode, out int bw, out int bh)
    {
        int w, h; var px = Load(path, out w, out h);
        int[] lab;
        var comps = Label(px, w, h, thr, out lab);
        int take = (mode == 0) ? 1 : 2;
        var wanted = new HashSet<int>();
        int minx = w, miny = h, maxx = -1, maxy = -1;
        for (int i = 0; i < take && i < comps.Count; i++)
        {
            wanted.Add(comps[i].Id);
            if (comps[i].MinX < minx) minx = comps[i].MinX;
            if (comps[i].MinY < miny) miny = comps[i].MinY;
            if (comps[i].MaxX > maxx) maxx = comps[i].MaxX;
            if (comps[i].MaxY > maxy) maxy = comps[i].MaxY;
        }
        // selection mask, dilated by 2 px to recover anti-aliased edges
        bool[] sel = new bool[w * h];
        for (int i = 0; i < w * h; i++) if (lab[i] != 0 && wanted.Contains(lab[i])) sel[i] = true;
        bool[] dil = new bool[w * h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                if (!sel[y * w + x]) continue;
                for (int dy = -2; dy <= 2; dy++)
                    for (int dx = -2; dx <= 2; dx++)
                    {
                        int nx = x + dx, ny = y + dy;
                        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
                        dil[ny * w + nx] = true;
                    }
            }
        int pad = 3;
        minx = Math.Max(0, minx - pad); miny = Math.Max(0, miny - pad);
        maxx = Math.Min(w - 1, maxx + pad); maxy = Math.Min(h - 1, maxy + pad);
        bw = maxx - minx + 1; bh = maxy - miny + 1;
        int[] outPx = new int[bw * bh];
        for (int y = 0; y < bh; y++)
            for (int x = 0; x < bw; x++)
            {
                int si = (y + miny) * w + (x + minx);
                int a = 0;
                if (dil[si])
                {
                    int l = Lum(px[si]);
                    // stretch: 20 -> 0, 190 -> 255
                    a = (int)Math.Round((l - 20) * 255.0 / 170.0);
                    if (a < 0) a = 0; if (a > 255) a = 255;
                }
                outPx[y * bw + x] = (a << 24) | 0x00FFFFFF;
            }
        var bmp = new Bitmap(bw, bh, PixelFormat.Format32bppArgb);
        var dd = bmp.LockBits(new Rectangle(0, 0, bw, bh), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        Marshal.Copy(outPx, 0, dd.Scan0, bw * bh);
        bmp.UnlockBits(dd);
        return bmp;
    }

    // BuildLogo + crop origin, so points measured in source coords can be mapped
    public static Bitmap BuildLogoAt(string path, int thr, int mode, out int bw, out int bh, out int cropX, out int cropY)
    {
        int w, h; var px = Load(path, out w, out h);
        int[] lab;
        var comps = Label(px, w, h, thr, out lab);
        int take = (mode == 0) ? 1 : 2;
        var wanted = new HashSet<int>();
        int minx = w, miny = h, maxx = -1, maxy = -1;
        for (int i = 0; i < take && i < comps.Count; i++)
        {
            wanted.Add(comps[i].Id);
            if (comps[i].MinX < minx) minx = comps[i].MinX;
            if (comps[i].MinY < miny) miny = comps[i].MinY;
            if (comps[i].MaxX > maxx) maxx = comps[i].MaxX;
            if (comps[i].MaxY > maxy) maxy = comps[i].MaxY;
        }
        bool[] sel = new bool[w * h];
        for (int i = 0; i < w * h; i++) if (lab[i] != 0 && wanted.Contains(lab[i])) sel[i] = true;
        bool[] dil = new bool[w * h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                if (!sel[y * w + x]) continue;
                for (int dy = -2; dy <= 2; dy++)
                    for (int dx = -2; dx <= 2; dx++)
                    {
                        int nx = x + dx, ny = y + dy;
                        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
                        dil[ny * w + nx] = true;
                    }
            }
        int pad = 3;
        minx = Math.Max(0, minx - pad); miny = Math.Max(0, miny - pad);
        maxx = Math.Min(w - 1, maxx + pad); maxy = Math.Min(h - 1, maxy + pad);
        cropX = minx; cropY = miny;
        bw = maxx - minx + 1; bh = maxy - miny + 1;
        int[] outPx = new int[bw * bh];
        for (int y = 0; y < bh; y++)
            for (int x = 0; x < bw; x++)
            {
                int si = (y + miny) * w + (x + minx);
                int a = 0;
                if (dil[si])
                {
                    int l = Lum(px[si]);
                    a = (int)Math.Round((l - 20) * 255.0 / 170.0);
                    if (a < 0) a = 0; if (a > 255) a = 255;
                }
                outPx[y * bw + x] = (a << 24) | 0x00FFFFFF;
            }
        var bmp = new Bitmap(bw, bh, PixelFormat.Format32bppArgb);
        var dd = bmp.LockBits(new Rectangle(0, 0, bw, bh), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        Marshal.Copy(outPx, 0, dd.Scan0, bw * bh);
        bmp.UnlockBits(dd);
        return bmp;
    }

    // Fit the circle of the logo ring (2nd largest component, the crescent).
    // Returns {cx, cy, outerR, innerR, midR, inlierAngles}
    public static double[] MeasureRing(string path, int thr)
    {
        int w, h; var px = Load(path, out w, out h);
        int[] lab;
        var comps = Label(px, w, h, thr, out lab);
        var ring = comps[1];                       // rank1 = crescent
        bool[] m = new bool[w * h];
        for (int i = 0; i < w * h; i++) m[i] = (lab[i] == ring.Id);

        int gx = (ring.MinX + ring.MaxX) / 2, gy = (ring.MinY + ring.MaxY) / 2;
        int rmax = (Math.Max(ring.MaxX - ring.MinX, ring.MaxY - ring.MinY)) / 2 + 25;
        int nAng = 360;
        int bestCx = gx, bestCy = gy, bestIn = -1; double bestMed = 0;
        for (int cy = gy - 25; cy <= gy + 25; cy++)
            for (int cx = gx - 25; cx <= gx + 25; cx++)
            {
                var vals = new List<double>();
                for (int a = 0; a < nAng; a++)
                {
                    double ang = a * 2.0 * Math.PI / nAng, ca = Math.Cos(ang), sa = Math.Sin(ang);
                    for (int r = rmax; r >= 20; r--)
                    {
                        int xi = (int)Math.Round(cx + ca * r), yi = (int)Math.Round(cy + sa * r);
                        if (xi < 0 || yi < 0 || xi >= w || yi >= h) continue;
                        if (m[yi * w + xi]) { vals.Add(r); break; }
                    }
                }
                if (vals.Count < 100) continue;
                vals.Sort();
                double med = vals[vals.Count / 2];
                int inl = 0;
                foreach (var v in vals) if (Math.Abs(v - med) <= 3) inl++;
                if (inl > bestIn) { bestIn = inl; bestCx = cx; bestCy = cy; bestMed = med; }
            }

        var outs = new List<double>(); var inns = new List<double>();
        for (int a = 0; a < nAng; a++)
        {
            double ang = a * 2.0 * Math.PI / nAng, ca = Math.Cos(ang), sa = Math.Sin(ang);
            int hit = -1;
            for (int r = rmax; r >= 20; r--)
            {
                int xi = (int)Math.Round(bestCx + ca * r), yi = (int)Math.Round(bestCy + sa * r);
                if (xi < 0 || yi < 0 || xi >= w || yi >= h) continue;
                if (m[yi * w + xi]) { hit = r; break; }
            }
            if (hit < 0 || Math.Abs(hit - bestMed) > 4) continue;
            outs.Add(hit);
            int rr = hit;
            while (rr > 20)
            {
                int xi = (int)Math.Round(bestCx + ca * (rr - 1)), yi = (int)Math.Round(bestCy + sa * (rr - 1));
                if (xi < 0 || yi < 0 || xi >= w || yi >= h) break;
                if (!m[yi * w + xi]) break;
                rr--;
            }
            inns.Add(rr);
        }
        outs.Sort(); inns.Sort();
        double mo = outs[outs.Count / 2], mi = inns[inns.Count / 2];
        return new double[] { bestCx, bestCy, mo, mi, (mo + mi) / 2.0, outs.Count };
    }

    // Place the mark by anchoring its ring circle onto a target circle.
    public static string MakeAnchored(string wheelPath, string logoPath, string outPath,
        double tcx, double tcy, double tR,
        double ringCx, double ringCy, double ringR,
        double opacity, double smokeMax, bool asPng)
    {
        int ww, wh; var wheel = Load(wheelPath, out ww, out wh);
        int bw, bh, cx0, cy0;
        using (var logo = BuildLogoAt(logoPath, 90, 1, out bw, out bh, out cx0, out cy0))
        {
            double scale = tR / ringR;
            double dw = bw * scale, dh = bh * scale;
            double ax = (ringCx - cx0) * scale, ay = (ringCy - cy0) * scale; // ring centre inside scaled bitmap
            double dx = tcx - ax, dy = tcy - ay;

            int[] layer;
            using (var canvas = new Bitmap(ww, wh, PixelFormat.Format32bppArgb))
            {
                using (var g = Graphics.FromImage(canvas))
                {
                    g.Clear(Color.FromArgb(0, 255, 255, 255));
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.CompositingQuality = CompositingQuality.HighQuality;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.DrawImage(logo, (float)dx, (float)dy, (float)dw, (float)dh);
                }
                var d = canvas.LockBits(new Rectangle(0, 0, ww, wh), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                layer = new int[ww * wh];
                Marshal.Copy(d.Scan0, layer, 0, ww * wh);
                canvas.UnlockBits(d);
            }

            int[] outPx = new int[ww * wh];
            for (int i = 0; i < ww * wh; i++)
            {
                int lp = layer[i]; int la = (lp >> 24) & 255; int bp = wheel[i];
                if (la == 0) { outPx[i] = bp | unchecked((int)0xFF000000); continue; }
                double a = (la / 255.0) * opacity;
                int bl = Lum(bp);
                double smoke = (bl - 140) / 110.0;
                if (smoke < 0) smoke = 0; if (smoke > 1) smoke = 1;
                a *= (1.0 - smoke * smokeMax);
                int br = (bp >> 16) & 255, bg = (bp >> 8) & 255, bb = bp & 255;
                outPx[i] = unchecked((int)0xFF000000)
                    | ((int)Math.Round(br + (255 - br) * a) << 16)
                    | ((int)Math.Round(bg + (255 - bg) * a) << 8)
                    | (int)Math.Round(bb + (255 - bb) * a);
            }
            SavePx(outPx, ww, wh, outPath, asPng);
            return string.Format("{0}  scale={1:0.000} mark {2:0}x{3:0} at ({4:0},{5:0}) ringR->{6:0}",
                System.IO.Path.GetFileName(outPath), scale, dw, dh, dx, dy, tR);
        }
    }

    // Average colour / saturation / local contrast of a patch, for probing regions.
    public static string Sample(string path, int[] pts, int half, string[] names)
    {
        int w, h; var px = Load(path, out w, out h);
        var sb = new StringBuilder();
        sb.AppendLine("name              x     y     R    G    B   lum  sat   std");
        for (int p = 0; p < pts.Length / 2; p++)
        {
            int cx = pts[p * 2], cy = pts[p * 2 + 1];
            double sr = 0, sg = 0, sb2 = 0, ss = 0, sl = 0, sl2 = 0; int c = 0;
            for (int y = cy - half; y <= cy + half; y++)
                for (int x = cx - half; x <= cx + half; x++)
                {
                    if (x < 0 || y < 0 || x >= w || y >= h) continue;
                    int v = px[y * w + x];
                    int r = (v >> 16) & 255, g = (v >> 8) & 255, b = v & 255;
                    sr += r; sg += g; sb2 += b;
                    int mx = Math.Max(r, Math.Max(g, b)), mn = Math.Min(r, Math.Min(g, b));
                    ss += mx - mn;
                    double l = (299.0 * r + 587.0 * g + 114.0 * b) / 1000.0;
                    sl += l; sl2 += l * l; c++;
                }
            double ml = sl / c, vr = sl2 / c - ml * ml;
            sb.AppendLine(string.Format("{0,-16} {1,4} {2,5} {3,5:0} {4,4:0} {5,4:0} {6,5:0} {7,4:0} {8,5:0.0}",
                names[p], cx, cy, sr / c, sg / c, sb2 / c, ml, ss / c, vr > 0 ? Math.Sqrt(vr) : 0));
        }
        return sb.ToString();
    }

    // Outer edge of the dark tyre: per angle, the largest radius still dark.
    public static string RadialDark(string path, int cx, int cy, int rFrom, int rTo, int darkThr, int nAng)
    {
        int w, h; var px = Load(path, out w, out h);
        var sb = new StringBuilder();
        var vals = new List<double>();
        for (int a = 0; a < nAng; a++)
        {
            double ang = a * 2.0 * Math.PI / nAng, ca = Math.Cos(ang), sa = Math.Sin(ang);
            int hit = -1;
            for (int r = rTo; r >= rFrom; r--)
            {
                int xi = (int)Math.Round(cx + ca * r), yi = (int)Math.Round(cy + sa * r);
                if (xi < 0 || yi < 0 || xi >= w || yi >= h) continue;
                if (Lum(px[yi * w + xi]) < darkThr) { hit = r; break; }
            }
            sb.Append(string.Format("{0,3}deg:{1,4}  ", a * 360 / nAng, hit));
            if ((a % 6) == 5) sb.AppendLine();
            if (hit > 0) vals.Add(hit);
        }
        sb.AppendLine();
        vals.Sort();
        sb.AppendLine(string.Format("n={0} p25={1} median={2} p75={3} max={4}",
            vals.Count, vals[vals.Count / 4], vals[vals.Count / 2], vals[vals.Count * 3 / 4], vals[vals.Count - 1]));
        return sb.ToString();
    }

    // Keep wheel + smoke, drop asphalt and bodywork.
    //   bodywork -> dark AND blue-dominant (B-R positive); smoke and asphalt are warm
    //   asphalt  -> textured (high local std); smoke is smooth
    //   tyre     -> dark, so it is held by the geometric wheel mask, not by colour
    public static string Cutout2(string srcPath, string outPath, string previewPath,
        int cx, int cy, double rHard, double feather,
        double lumLo, double lumHi, double stdLo, double stdHi,
        double coolLo, double coolHi, double rFade, double fadeSoft,
        double yCut, double yCutSoft, double smokeFloor, int win, int blurRadius)
    {
        int w, h; var px = Load(srcPath, out w, out h);
        int n = w * h;
        var lum = new double[n];
        var cool = new double[n];
        for (int i = 0; i < n; i++)
        {
            int p = px[i]; int r = (p >> 16) & 255, g = (p >> 8) & 255, b = p & 255;
            lum[i] = (299.0 * r + 587.0 * g + 114.0 * b) / 1000.0;
            // "magenta-ness": the car is purple, so its green channel sits below red and blue.
            // Bodywork measures +10..+14, smoke and asphalt -5..+4. Cleanest separator found.
            cool[i] = (r + b) / 2.0 - g;
        }
        var s1 = new double[(w + 1) * (h + 1)];
        var s2 = new double[(w + 1) * (h + 1)];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                double v = lum[y * w + x];
                s1[(y + 1) * (w + 1) + (x + 1)] = v + s1[y * (w + 1) + (x + 1)] + s1[(y + 1) * (w + 1) + x] - s1[y * (w + 1) + x];
                s2[(y + 1) * (w + 1) + (x + 1)] = v * v + s2[y * (w + 1) + (x + 1)] + s2[(y + 1) * (w + 1) + x] - s2[y * (w + 1) + x];
            }
        var std = new double[n];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                int x0 = Math.Max(0, x - win), y0 = Math.Max(0, y - win);
                int x1 = Math.Min(w - 1, x + win), y1 = Math.Min(h - 1, y + win);
                double cnt = (x1 - x0 + 1) * (y1 - y0 + 1);
                double a1 = s1[(y1 + 1) * (w + 1) + (x1 + 1)] - s1[y0 * (w + 1) + (x1 + 1)] - s1[(y1 + 1) * (w + 1) + x0] + s1[y0 * (w + 1) + x0];
                double a2 = s2[(y1 + 1) * (w + 1) + (x1 + 1)] - s2[y0 * (w + 1) + (x1 + 1)] - s2[(y1 + 1) * (w + 1) + x0] + s2[y0 * (w + 1) + x0];
                double m = a1 / cnt, v = a2 / cnt - m * m;
                std[y * w + x] = v > 0 ? Math.Sqrt(v) : 0;
            }

        var alpha = new double[n];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                int i = y * w + x;
                double dx = x - cx, dy = y - cy;
                double rr = Math.Sqrt(dx * dx + dy * dy);
                double wheel = rr <= rHard ? 1.0 : (rr >= rHard + feather ? 0.0 : 1.0 - (rr - rHard) / feather);

                double b = Clamp01((lum[i] - lumLo) / (lumHi - lumLo));
                double t = Clamp01(1.0 - (std[i] - stdLo) / (stdHi - stdLo));
                double c = Clamp01(1.0 - (cool[i] - coolLo) / (coolHi - coolLo));
                double d = rr <= rFade ? 1.0 : (rr >= rFade + fadeSoft ? 0.0 : 1.0 - (rr - rFade) / fadeSoft);
                double yk = y <= yCut ? 1.0 : (y >= yCut + yCutSoft ? 0.0 : 1.0 - (y - yCut) / yCutSoft);

                double smoke = b * t * c * d * yk;
                if (smokeFloor > 0) smoke = Clamp01((smoke - smokeFloor) / (1.0 - smokeFloor));
                alpha[i] = Math.Max(wheel, smoke);
            }

        if (blurRadius > 0)
        {
            var tmp = new double[n];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    double acc = 0; int c = 0;
                    for (int d2 = -blurRadius; d2 <= blurRadius; d2++)
                    { int xx = x + d2; if (xx < 0 || xx >= w) continue; acc += alpha[y * w + xx]; c++; }
                    tmp[y * w + x] = acc / c;
                }
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    double acc = 0; int c = 0;
                    for (int d2 = -blurRadius; d2 <= blurRadius; d2++)
                    { int yy = y + d2; if (yy < 0 || yy >= h) continue; acc += tmp[yy * w + x]; c++; }
                    double dx = x - cx, dy = y - cy;
                    double v = acc / c;
                    if (Math.Sqrt(dx * dx + dy * dy) <= rHard) v = 1.0;
                    alpha[y * w + x] = v;
                }
        }

        var outPx = new int[n];
        for (int i = 0; i < n; i++)
        {
            int a = (int)Math.Round(Clamp01(alpha[i]) * 255);
            outPx[i] = (a << 24) | (px[i] & 0x00FFFFFF);
        }
        SavePx(outPx, w, h, outPath, true);

        var prev = new int[n];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                int i = y * w + x;
                double a = Clamp01(alpha[i]);
                int bgv = (x < w / 2) ? 26 : 245;
                int p = px[i];
                prev[i] = unchecked((int)0xFF000000)
                    | ((int)Math.Round(((p >> 16) & 255) * a + bgv * (1 - a)) << 16)
                    | ((int)Math.Round(((p >> 8) & 255) * a + bgv * (1 - a)) << 8)
                    | (int)Math.Round((p & 255) * a + bgv * (1 - a));
            }
        SavePx(prev, w, h, previewPath, false);
        return "cutout -> " + System.IO.Path.GetFileName(outPath) + " / " + System.IO.Path.GetFileName(previewPath);
    }

    static double Clamp01(double v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }

    // Crop a transparent PNG to its visible content plus a margin.
    public static string Trim(string srcPath, string outPath, int alphaThr, int margin)
    {
        using (var src = new Bitmap(srcPath))
        {
            int w = src.Width, h = src.Height;
            var d = src.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            var px = new int[w * h];
            Marshal.Copy(d.Scan0, px, 0, w * h);
            src.UnlockBits(d);
            int minx = w, miny = h, maxx = -1, maxy = -1;
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                    if (((px[y * w + x] >> 24) & 255) > alphaThr)
                    {
                        if (x < minx) minx = x; if (x > maxx) maxx = x;
                        if (y < miny) miny = y; if (y > maxy) maxy = y;
                    }
            if (maxx < 0) return "trim: nothing visible";
            minx = Math.Max(0, minx - margin); miny = Math.Max(0, miny - margin);
            maxx = Math.Min(w - 1, maxx + margin); maxy = Math.Min(h - 1, maxy + margin);
            int nw = maxx - minx + 1, nh = maxy - miny + 1;
            var outPx = new int[nw * nh];
            for (int y = 0; y < nh; y++)
                for (int x = 0; x < nw; x++)
                    outPx[y * nw + x] = px[(y + miny) * w + (x + minx)];
            SavePx(outPx, nw, nh, outPath, true);
            return string.Format("trim {0}x{1} -> {2}x{3} (crop {4},{5})", w, h, nw, nh, minx, miny);
        }
    }

    // Composite an RGBA png over a flat colour, for previewing a matte.
    public static string OverBg(string srcPath, string outPath, int rr, int gg, int bb)
    {
        using (var src = new Bitmap(srcPath))
        {
            int w = src.Width, h = src.Height;
            var d = src.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            var px = new int[w * h];
            Marshal.Copy(d.Scan0, px, 0, w * h);
            src.UnlockBits(d);
            var outPx = new int[w * h];
            for (int i = 0; i < w * h; i++)
            {
                int p = px[i]; double a = ((p >> 24) & 255) / 255.0;
                outPx[i] = unchecked((int)0xFF000000)
                    | ((int)Math.Round(((p >> 16) & 255) * a + rr * (1 - a)) << 16)
                    | ((int)Math.Round(((p >> 8) & 255) * a + gg * (1 - a)) << 8)
                    | (int)Math.Round((p & 255) * a + bb * (1 - a));
            }
            SavePx(outPx, w, h, outPath, false);
            return "preview on bg -> " + System.IO.Path.GetFileName(outPath);
        }
    }

    public static string Cutout(string srcPath, string outPath, string previewPath,
        int cx, int cy, double rHard, double feather,
        double lumLo, double lumHi, double stdLo, double stdHi,
        double satLo, double satHi, double rFade, double fadeSoft, int blurRadius)
    {
        int w, h; var px = Load(srcPath, out w, out h);
        int n = w * h;
        var lum = new double[n];
        var sat = new double[n];
        for (int i = 0; i < n; i++)
        {
            int p = px[i]; int r = (p >> 16) & 255, g = (p >> 8) & 255, b = p & 255;
            lum[i] = (299.0 * r + 587.0 * g + 114.0 * b) / 1000.0;
            int mx = Math.Max(r, Math.Max(g, b)), mn = Math.Min(r, Math.Min(g, b));
            sat[i] = mx - mn;
        }
        // local std via integral images
        var s1 = new double[(w + 1) * (h + 1)];
        var s2 = new double[(w + 1) * (h + 1)];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                double v = lum[y * w + x];
                s1[(y + 1) * (w + 1) + (x + 1)] = v + s1[y * (w + 1) + (x + 1)] + s1[(y + 1) * (w + 1) + x] - s1[y * (w + 1) + x];
                s2[(y + 1) * (w + 1) + (x + 1)] = v * v + s2[y * (w + 1) + (x + 1)] + s2[(y + 1) * (w + 1) + x] - s2[y * (w + 1) + x];
            }
        int k = 3; // 7x7 window
        var std = new double[n];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                int x0 = Math.Max(0, x - k), y0 = Math.Max(0, y - k);
                int x1 = Math.Min(w - 1, x + k), y1 = Math.Min(h - 1, y + k);
                double cnt = (x1 - x0 + 1) * (y1 - y0 + 1);
                double a1 = s1[(y1 + 1) * (w + 1) + (x1 + 1)] - s1[y0 * (w + 1) + (x1 + 1)] - s1[(y1 + 1) * (w + 1) + x0] + s1[y0 * (w + 1) + x0];
                double a2 = s2[(y1 + 1) * (w + 1) + (x1 + 1)] - s2[y0 * (w + 1) + (x1 + 1)] - s2[(y1 + 1) * (w + 1) + x0] + s2[y0 * (w + 1) + x0];
                double m = a1 / cnt;
                double v = a2 / cnt - m * m;
                std[y * w + x] = v > 0 ? Math.Sqrt(v) : 0;
            }

        var alpha = new double[n];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                int i = y * w + x;
                double dx = x - cx, dy = y - cy;
                double rr = Math.Sqrt(dx * dx + dy * dy);

                double wheel = rr <= rHard ? 1.0 : (rr >= rHard + feather ? 0.0 : 1.0 - (rr - rHard) / feather);

                double b = (lum[i] - lumLo) / (lumHi - lumLo);
                b = b < 0 ? 0 : (b > 1 ? 1 : b);
                double t = 1.0 - (std[i] - stdLo) / (stdHi - stdLo);
                t = t < 0 ? 0 : (t > 1 ? 1 : t);
                double sk = 1.0 - (sat[i] - satLo) / (satHi - satLo);
                sk = sk < 0 ? 0 : (sk > 1 ? 1 : sk);
                double d = rr <= rFade ? 1.0 : (rr >= rFade + fadeSoft ? 0.0 : 1.0 - (rr - rFade) / fadeSoft);
                double smoke = b * t * sk * d;

                alpha[i] = Math.Max(wheel, smoke);
            }

        // soften the matte
        if (blurRadius > 0)
        {
            var tmp = new double[n];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    double acc = 0; int c = 0;
                    for (int d2 = -blurRadius; d2 <= blurRadius; d2++)
                    { int xx = x + d2; if (xx < 0 || xx >= w) continue; acc += alpha[y * w + xx]; c++; }
                    tmp[y * w + x] = acc / c;
                }
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    double acc = 0; int c = 0;
                    for (int d2 = -blurRadius; d2 <= blurRadius; d2++)
                    { int yy = y + d2; if (yy < 0 || yy >= h) continue; acc += tmp[yy * w + x]; c++; }
                    double dx = x - cx, dy = y - cy;
                    double rr = Math.Sqrt(dx * dx + dy * dy);
                    double v = acc / c;
                    if (rr <= rHard) v = 1.0;          // never soften inside the wheel
                    alpha[y * w + x] = v;
                }
        }

        var outPx = new int[n];
        for (int i = 0; i < n; i++)
        {
            int a = (int)Math.Round(alpha[i] * 255);
            if (a < 0) a = 0; if (a > 255) a = 255;
            outPx[i] = (a << 24) | (px[i] & 0x00FFFFFF);
        }
        SavePx(outPx, w, h, outPath, true);

        // preview: left half on charcoal, right half on white
        var prev = new int[n];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                int i = y * w + x;
                double a = alpha[i];
                int bgv = (x < w / 2) ? 26 : 245;
                int p = px[i];
                int r = (int)Math.Round(((p >> 16) & 255) * a + bgv * (1 - a));
                int g = (int)Math.Round(((p >> 8) & 255) * a + bgv * (1 - a));
                int b = (int)Math.Round((p & 255) * a + bgv * (1 - a));
                prev[i] = unchecked((int)0xFF000000) | (r << 16) | (g << 8) | b;
            }
        SavePx(prev, w, h, previewPath, false);
        return "cutout -> " + System.IO.Path.GetFileName(outPath) + " / " + System.IO.Path.GetFileName(previewPath);
    }

    public static string ExportLogo(string path, string outPath, int thr, int mode)
    {
        int bw, bh;
        using (var b = BuildLogo(path, thr, mode, out bw, out bh))
        {
            b.Save(outPath, ImageFormat.Png);
            return string.Format("logo mode={0} -> {1}x{2}  {3}", mode, bw, bh, outPath);
        }
    }

    // ---------------- composite ----------------
    public static string MakeVariant(string wheelPath, string logoPath, string outPath,
        int cx, int cy, double rTarget, int mode, double fill, double opacity,
        double smokeMax, double offX, double offY, bool asPng)
    {
        int ww, wh; var wheel = Load(wheelPath, out ww, out wh);
        int bw, bh;
        using (var logo = BuildLogo(logoPath, 90, mode, out bw, out bh))
        {
            double scale;
            if (mode == 0) scale = (2.0 * rTarget * fill) / bw;
            else scale = (2.0 * rTarget * fill) / Math.Max(bw, bh);
            double dw = bw * scale, dh = bh * scale;
            double dx = cx - dw / 2.0 + offX, dy = cy - dh / 2.0 + offY;

            int[] layer;
            using (var canvas = new Bitmap(ww, wh, PixelFormat.Format32bppArgb))
            {
                using (var g = Graphics.FromImage(canvas))
                {
                    g.Clear(Color.FromArgb(0, 255, 255, 255));
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.CompositingQuality = CompositingQuality.HighQuality;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.DrawImage(logo, (float)dx, (float)dy, (float)dw, (float)dh);
                }
                var d = canvas.LockBits(new Rectangle(0, 0, ww, wh), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                layer = new int[ww * wh];
                Marshal.Copy(d.Scan0, layer, 0, ww * wh);
                canvas.UnlockBits(d);
            }

            int[] outPx = new int[ww * wh];
            for (int i = 0; i < ww * wh; i++)
            {
                int lp = layer[i];
                int la = (lp >> 24) & 255;
                int bp = wheel[i];
                if (la == 0) { outPx[i] = bp | unchecked((int)0xFF000000); continue; }
                double a = (la / 255.0) * opacity;
                int bl = Lum(bp);
                double smoke = (bl - 140) / 110.0;
                if (smoke < 0) smoke = 0; if (smoke > 1) smoke = 1;
                a *= (1.0 - smoke * smokeMax);
                int br = (bp >> 16) & 255, bg = (bp >> 8) & 255, bb = bp & 255;
                int r = (int)Math.Round(br + (255 - br) * a);
                int gg = (int)Math.Round(bg + (255 - bg) * a);
                int b2 = (int)Math.Round(bb + (255 - bb) * a);
                outPx[i] = unchecked((int)0xFF000000) | (r << 16) | (gg << 8) | b2;
            }
            SavePx(outPx, ww, wh, outPath, asPng);
            return string.Format("{0}  mode={1} logo {2}x{3} -> {4:0}x{5:0} at ({6:0},{7:0})",
                outPath, mode, bw, bh, dw, dh, dx, dy);
        }
    }
}
