<#
.SYNOPSIS
  Reads WoW combat log files and writes (1) a Markdown report on your DPS,
  healing and tanking, and (2) Learned\CombatLog.lua, which Flow loads to use
  what was learned (spell order bias, real heal sizes, how hard mobs hit).

.HOW TO USE
  In game: /flow log auto  (or type /combatlog each session). Play.
  Then run:  powershell -ExecutionPolicy Bypass -File tools\analyze-combatlog.ps1
  In game: /reload so Flow picks up the new learned file.

  Keep "Advanced Combat Logging" OFF (System > Network). The script copes
  with it on, but the plain format is simpler and smaller.
#>
param(
    [string]$LogDir,                 # default: <your WoW: Forever folder>\Logs (tools\Common.ps1)
    [string[]]$Files,
    [string]$ReportDir = $(if ($env:FLOW_REPORT_DIR) { $env:FLOW_REPORT_DIR } else { Join-Path $PSScriptRoot '..\reports' }),
    [string]$LearnedOut = (Join-Path $PSScriptRoot '..\Learned\CombatLog.lua'),
    [int]$MinFightSeconds = 6
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
if (-not $LogDir -and -not $Files) {
    $wow = Find-WowDir
    if (-not $wow) { throw "Can't find your WoW: Forever folder. Pass -LogDir or set FLOW_WOW_DIR." }
    $LogDir = Join-Path $wow 'Logs'
}

$source = @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace FlowLog {

public class Fight {
    public double Start, End;
    public double Damage, Healing, Overheal, Taken;
    public Dictionary<string, double> DmgBySpell = new Dictionary<string, double>();
    public Dictionary<string, int> Casts = new Dictionary<string, int>();
    public List<string> Opener = new List<string>();
    public HashSet<string> Enemies = new HashSet<string>();
    public Dictionary<string, double> TakenBySource = new Dictionary<string, double>();
    public int Kills, Deaths, Swings, Dodges, Parries, Blocks, Misses;
    public bool Boss;
    public double SealUptime;
    public string Type = "normal";
    public double Duration { get { return Math.Max(0.5, End - Start); } }
    public double Dps { get { return Damage / Duration; } }
}

public class SpellStat { public double Damage; public int Hits, Crits; }
public class HealStat { public int Hits, Crits, NonCritN; public double NonCritSum, Total, Over; }

public class Analyzer {
    public int MinFight = 6;
    public List<Fight> Fights = new List<Fight>();
    public Dictionary<string, SpellStat> Spells = new Dictionary<string, SpellStat>();
    public Dictionary<string, HealStat> Heals = new Dictionary<string, HealStat>();
    public long Lines;
    public int FilesRead;
    public string Build = "?";
    public bool AdvancedSeen;

    Fight cur;
    double lastActivity = -1;
    bool advanced;
    int adv = -1;
    bool inEncounter;
    double sealSince = -1;
    List<double[]> sealIntervals = new List<double[]>();
    List<KeyValuePair<double, string>> recentCasts = new List<KeyValuePair<double, string>>();
    Dictionary<string, double> dayCache = new Dictionary<string, double>();
    double lastT;

    const long MINE = 0x1, FRIENDLY = 0x10, PLAYER = 0x400, NPC = 0x800;

    static bool IsMe(long f) { return (f & MINE) != 0 && (f & PLAYER) != 0; }
    static bool IsMine(long f) { return (f & MINE) != 0; }
    static bool IsEnemy(long f) { return (f & MINE) == 0 && (f & FRIENDLY) == 0 && (f & NPC) != 0; }

    static long Hex(string s) {
        if (s == null || s.Length < 3) return 0;
        try { return Convert.ToInt64(s.Substring(2), 16); } catch { return 0; }
    }
    static double Num(string s) {
        double d;
        if (s != null && double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out d)) return d;
        return 0;
    }

    static string[] Split(string s, int start) {
        var list = new List<string>(48);
        var sb = new StringBuilder();
        bool q = false;
        for (int i = start; i < s.Length; i++) {
            char c = s[i];
            if (c == '"') { q = !q; continue; }
            if (c == ',' && !q) { list.Add(sb.ToString()); sb.Length = 0; continue; }
            sb.Append(c);
        }
        list.Add(sb.ToString());
        return list.ToArray();
    }

    // "11/5/2026 17:30:12.3451-8" or "11/5 17:30:12.345" -> seconds
    double Time(string ts) {
        int sp = ts.IndexOf(' ');
        if (sp < 0) return lastT;
        string date = ts.Substring(0, sp), time = ts.Substring(sp + 1);
        double day;
        if (!dayCache.TryGetValue(date, out day)) {
            string[] d = date.Split('/');
            int month = int.Parse(d[0]), dd = int.Parse(d[1]);
            int year = d.Length > 2 ? int.Parse(d[2]) : 2000;
            day = (new DateTime(year, month, dd) - new DateTime(2000, 1, 1)).TotalDays * 86400.0;
            dayCache[date] = day;
        }
        int dot = time.IndexOf('.');
        int tz = -1;
        if (dot >= 0) { tz = time.IndexOfAny(new[] { '-', '+' }, dot); }
        if (tz > 0) time = time.Substring(0, tz);
        string[] hms = time.Split(':');
        double secs = int.Parse(hms[0]) * 3600 + int.Parse(hms[1]) * 60
            + double.Parse(hms[2], CultureInfo.InvariantCulture);
        lastT = day + secs;
        return lastT;
    }

    static int PrefixLen(string ev) {
        if (ev.StartsWith("SWING_")) return 0;
        if (ev.StartsWith("SPELL_") || ev.StartsWith("RANGE_") || ev.StartsWith("DAMAGE_")) return 3;
        if (ev.StartsWith("ENVIRONMENTAL_")) return 1;
        return 0;
    }
    static string Suffix(string ev) {
        if (ev.StartsWith("SPELL_PERIODIC_") || ev.StartsWith("SPELL_BUILDING_")) return ev.Substring(15);
        if (ev.StartsWith("SPELL_") || ev.StartsWith("RANGE_") || ev.StartsWith("SWING_")) return ev.Substring(6);
        if (ev.StartsWith("ENVIRONMENTAL_")) return ev.Substring(14);
        return ev;
    }
    static bool AdvancedSuffix(string s) {
        return s == "DAMAGE" || s == "DAMAGE_LANDED" || s == "HEAL" || s == "ENERGIZE"
            || s == "DRAIN" || s == "LEECH" || s == "CAST_SUCCESS";
    }

    void Activity(double t) {
        if (cur == null || t - lastActivity > 5) {
            Close();
            cur = new Fight();
            cur.Start = t;
            // A pull spell is cast just before the first hit lands.
            foreach (var c in recentCasts) {
                if (t - c.Key <= 2.0) AddCast(c.Value);
            }
        }
        lastActivity = t;
        cur.End = t;
        if (inEncounter) cur.Boss = true;
    }

    void AddCast(string spell) {
        int n;
        cur.Casts.TryGetValue(spell, out n);
        cur.Casts[spell] = n + 1;
        if (cur.Opener.Count < 3) cur.Opener.Add(spell);
    }

    void Close() {
        if (cur == null) return;
        if (cur.End - cur.Start >= 2) {
            cur.Type = cur.Boss ? "boss" : (cur.Enemies.Count >= 3 ? "aoe" : "normal");
            Fights.Add(cur);
        }
        cur = null;
    }

    public void ReadFile(string path) {
        FilesRead++;
        cur = null; lastActivity = -1; adv = -1; advanced = false; sealSince = -1;
        using (var r = new StreamReader(path, Encoding.UTF8, true, 1 << 16)) {
            string line;
            while ((line = r.ReadLine()) != null) {
                Lines++;
                int gap = line.IndexOf("  ");
                if (gap < 0) continue;
                try { Handle(Time(line.Substring(0, gap)), Split(line, gap + 2)); }
                catch (Exception) { /* skip malformed line */ }
            }
        }
        if (sealSince >= 0) { sealIntervals.Add(new[] { sealSince, lastT }); sealSince = -1; }
        Close();
    }

    void Handle(double t, string[] f) {
        string ev = f[0];
        if (ev == "COMBAT_LOG_VERSION") {
            for (int i = 1; i + 1 < f.Length; i++) {
                if (f[i] == "ADVANCED_LOG_ENABLED") { advanced = f[i + 1] == "1"; if (advanced) AdvancedSeen = true; }
                if (f[i] == "BUILD_VERSION") Build = f[i + 1];
            }
            return;
        }
        if (ev == "ENCOUNTER_START") { inEncounter = true; return; }
        if (ev == "ENCOUNTER_END") { inEncounter = false; return; }
        if (f.Length < 9) return;

        long sf = Hex(f[3]), df = Hex(f[7]);
        bool srcMe = IsMe(sf), srcMine = IsMine(sf), dstMe = IsMe(df);
        bool srcEnemy = IsEnemy(sf), dstEnemy = IsEnemy(df);
        int prefix = PrefixLen(ev);
        string suffix = Suffix(ev);

        if (advanced && adv < 0 && ev == "SPELL_CAST_SUCCESS") adv = f.Length - 12;
        bool hasAdv = advanced && AdvancedSuffix(suffix);
        if (hasAdv && adv < 0) return;  // can't place fields yet
        int b = 9 + prefix + (hasAdv ? adv : 0);
        string spell = prefix == 3 && f.Length > 10 ? f[10]
                     : ev.StartsWith("SWING_") ? "Auto Attack" : ev;

        if (suffix == "DAMAGE" && f.Length > b) {
            double amount = Num(f[b]);
            int S = f.Length - b;
            bool crit = S >= 10 && f[b + S - 4] == "1";
            if (srcMine && dstEnemy) {
                Activity(t);
                cur.Damage += amount;
                double d; cur.DmgBySpell.TryGetValue(spell, out d); cur.DmgBySpell[spell] = d + amount;
                cur.Enemies.Add(f[5]);
                SpellStat st;
                if (!Spells.TryGetValue(spell, out st)) { st = new SpellStat(); Spells[spell] = st; }
                st.Damage += amount; st.Hits++; if (crit) st.Crits++;
            } else if (dstMe && srcEnemy) {
                Activity(t);
                cur.Taken += amount;
                double d; cur.TakenBySource.TryGetValue(f[2], out d); cur.TakenBySource[f[2]] = d + amount;
                if (ev == "SWING_DAMAGE") cur.Swings++;
            }
        } else if (suffix == "HEAL" && srcMe && f.Length > b) {
            double amount = Num(f[b]);
            int S = f.Length - b;
            double over = S >= 4 ? Num(f[b + S - 3]) : 0;
            bool crit = S >= 4 && f[b + S - 1] == "1";
            HealStat h;
            if (!Heals.TryGetValue(spell, out h)) { h = new HealStat(); Heals[spell] = h; }
            h.Hits++; h.Total += amount; h.Over += over;
            if (crit) h.Crits++; else { h.NonCritN++; h.NonCritSum += amount; }
            if (cur != null && t - lastActivity <= 5) { cur.Healing += amount - over; cur.Overheal += over; }
        } else if (suffix == "MISSED" && dstMe && srcEnemy && f.Length > b) {
            Activity(t);
            string miss = f[b];
            if (ev == "SWING_MISSED") cur.Swings++;
            if (miss == "DODGE") cur.Dodges++;
            else if (miss == "PARRY") cur.Parries++;
            else if (miss == "BLOCK") cur.Blocks++;
            else if (miss == "MISS") cur.Misses++;
        } else if (ev == "SPELL_CAST_SUCCESS" && srcMe) {
            if (cur != null && t - lastActivity <= 5) AddCast(spell);
            recentCasts.Add(new KeyValuePair<double, string>(t, spell));
            if (recentCasts.Count > 6) recentCasts.RemoveAt(0);
        } else if ((ev == "SPELL_AURA_APPLIED" || ev == "SPELL_AURA_REMOVED") && srcMe && dstMe
                   && spell.StartsWith("Seal of")) {
            if (ev == "SPELL_AURA_APPLIED") { if (sealSince < 0) sealSince = t; }
            else if (sealSince >= 0) { sealIntervals.Add(new[] { sealSince, t }); sealSince = -1; }
        } else if (ev == "UNIT_DIED") {
            if (dstEnemy && cur != null && t - lastActivity <= 5) cur.Kills++;
            if (dstMe && cur != null) cur.Deaths++;
        }
    }

    public void Finish() {
        foreach (var fight in Fights) {
            double up = 0;
            foreach (var iv in sealIntervals) {
                double a = Math.Max(iv[0], fight.Start), z = Math.Min(iv[1], fight.End);
                if (z > a) up += z - a;
            }
            fight.SealUptime = Math.Min(1.0, up / fight.Duration);
        }
    }

    // ---------------------------------------------------------------- analysis

    public List<Fight> Usable(string type) {
        var list = new List<Fight>();
        foreach (var f in Fights)
            if (f.Duration >= MinFight && f.Damage > 0 && (type == "all" || f.Type == type)) list.Add(f);
        list.Sort((a, b) => b.Dps.CompareTo(a.Dps));
        return list;
    }

    static double Cpm(Fight f, string spell) {
        int n; f.Casts.TryGetValue(spell, out n);
        return n / (f.Duration / 60.0);
    }

    public class Diff { public string Spell; public double Top, Bottom, Bias; }

    public List<Diff> Compare(List<Fight> list, out List<Fight> top, out List<Fight> bottom) {
        int third = Math.Max(2, list.Count / 3);
        top = list.GetRange(0, third);
        bottom = list.GetRange(list.Count - third, third);
        var spells = new HashSet<string>();
        foreach (var f in list) foreach (var k in f.Casts.Keys) spells.Add(k);
        var diffs = new List<Diff>();
        foreach (var s in spells) {
            double t = 0, b = 0;
            foreach (var f in top) t += Cpm(f, s);
            foreach (var f in bottom) b += Cpm(f, s);
            t /= top.Count; b /= bottom.Count;
            double bias = (t - b) / Math.Max(Math.Max(t, b), 0.5);
            diffs.Add(new Diff { Spell = s, Top = t, Bottom = b, Bias = Math.Max(-1, Math.Min(1, bias)) });
        }
        diffs.Sort((x, y) => Math.Abs(y.Bias).CompareTo(Math.Abs(x.Bias)));
        return diffs;
    }

    static double Avg(List<Fight> l, Func<Fight, double> fn) {
        if (l.Count == 0) return 0;
        double s = 0; foreach (var f in l) s += fn(f); return s / l.Count;
    }

    static string F1(double v) { return v.ToString("0.0", CultureInfo.InvariantCulture); }
    static string F0(double v) { return v.ToString("0", CultureInfo.InvariantCulture); }
    static string Pct(double v) { return (v * 100).ToString("0", CultureInfo.InvariantCulture) + "%"; }

    public string Report(string date) {
        var sb = new StringBuilder();
        var all = Usable("all");
        double dmg = 0, dur = 0, taken = 0;
        int deaths = 0, kills = 0;
        foreach (var f in Fights) { dmg += f.Damage; dur += f.Duration; taken += f.Taken; deaths += f.Deaths; kills += f.Kills; }

        sb.AppendLine("# Combat report " + date);
        sb.AppendLine();
        sb.AppendLine("Back to [[00 Overview]] | Made by `tools/analyze-combatlog.ps1` from " + FilesRead
            + " log file(s), " + Lines + " lines, client " + Build + ".");
        sb.AppendLine();
        sb.AppendLine("## Summary");
        sb.AppendLine();
        sb.AppendLine("| | |");
        sb.AppendLine("|---|---|");
        sb.AppendLine("| Fights | " + Fights.Count + " (" + all.Count + " at least " + MinFight + "s long) |");
        sb.AppendLine("| Time in combat | " + F0(dur / 60) + " min |");
        sb.AppendLine("| Average DPS | " + F1(dur > 0 ? dmg / dur : 0) + " |");
        sb.AppendLine("| Kills / deaths | " + kills + " / " + deaths + " |");
        sb.AppendLine("| Damage taken per second | " + F1(dur > 0 ? taken / dur : 0) + " |");
        sb.AppendLine();

        // ---- DPS
        sb.AppendLine("## DPS (Retribution)");
        sb.AppendLine();
        sb.AppendLine("| Fight type | Fights | Average DPS | Best | Typical length |");
        sb.AppendLine("|---|---|---|---|---|");
        foreach (var type in new[] { "normal", "aoe", "boss" }) {
            var l = Usable(type);
            if (l.Count == 0) continue;
            sb.AppendLine("| " + type + " | " + l.Count + " | " + F1(Avg(l, x => x.Dps)) + " | "
                + F1(l[0].Dps) + " | " + F0(Avg(l, x => x.Duration)) + "s |");
        }
        sb.AppendLine();

        sb.AppendLine("### Where your damage comes from");
        sb.AppendLine();
        sb.AppendLine("| Spell | Damage | Share | Hits | Crit |");
        sb.AppendLine("|---|---|---|---|---|");
        var spellList = new List<KeyValuePair<string, SpellStat>>(Spells);
        spellList.Sort((a, b) => b.Value.Damage.CompareTo(a.Value.Damage));
        double totalSpell = 0; foreach (var kv in spellList) totalSpell += kv.Value.Damage;
        foreach (var kv in spellList)
            sb.AppendLine("| " + kv.Key + " | " + F0(kv.Value.Damage) + " | " + Pct(totalSpell > 0 ? kv.Value.Damage / totalSpell : 0)
                + " | " + kv.Value.Hits + " | " + Pct(kv.Value.Hits > 0 ? (double)kv.Value.Crits / kv.Value.Hits : 0) + " |");
        sb.AppendLine();

        var recs = new List<string>();
        sb.AppendLine("### Best fights vs worst fights");
        sb.AppendLine();
        foreach (var type in new[] { "normal", "aoe", "boss", "all" }) {
            var l = Usable(type);
            if (l.Count < 6) {
                if (type == "all") sb.AppendLine("Not enough fights yet (" + l.Count + " of 6) to compare. Keep logging.");
                continue;
            }
            List<Fight> top, bottom;
            var diffs = Compare(l, out top, out bottom);
            sb.AppendLine("**" + (type == "all" ? "All fights" : type) + "** (" + l.Count + " fights): best third "
                + F1(Avg(top, x => x.Dps)) + " DPS, worst third " + F1(Avg(bottom, x => x.Dps)) + " DPS.");
            sb.AppendLine();
            sb.AppendLine("| Spell | Casts/min in best | Casts/min in worst | Lean |");
            sb.AppendLine("|---|---|---|---|");
            int shown = 0;
            foreach (var d in diffs) {
                if (shown++ >= 6) break;
                sb.AppendLine("| " + d.Spell + " | " + F1(d.Top) + " | " + F1(d.Bottom) + " | "
                    + (d.Bias > 0.15 ? "more" : d.Bias < -0.15 ? "less" : "same") + " |");
            }
            double sealTop = Avg(top, x => x.SealUptime), sealBot = Avg(bottom, x => x.SealUptime);
            sb.AppendLine();
            sb.AppendLine("Seal uptime: " + Pct(sealTop) + " in best fights, " + Pct(sealBot) + " in worst. "
                + "Enemies per fight: " + F1(Avg(top, x => x.Enemies.Count)) + " vs " + F1(Avg(bottom, x => x.Enemies.Count)) + ".");
            var openers = new Dictionary<string, int>();
            foreach (var f in top) if (f.Opener.Count > 0) {
                string o = string.Join(" > ", f.Opener.ToArray());
                int n; openers.TryGetValue(o, out n); openers[o] = n + 1;
            }
            string bestOpener = null; int bestN = 0;
            foreach (var kv in openers) if (kv.Value > bestN) { bestOpener = kv.Key; bestN = kv.Value; }
            if (bestOpener != null) sb.AppendLine("Most common opener in your best fights: **" + bestOpener + "**.");
            sb.AppendLine();

            if (type == "all") {
                if (sealTop - sealBot >= 0.1)
                    recs.Add("Keep your seal up: it was up " + Pct(sealTop) + " of the time in your best fights vs " + Pct(sealBot) + " in your worst.");
                foreach (var d in diffs) {
                    if (d.Bias >= 0.25 && d.Top >= 0.5 && d.Spell != "Auto Attack")
                        recs.Add("Use " + d.Spell + " more: " + F1(d.Top) + "/min in your best fights vs " + F1(d.Bottom) + "/min in your worst.");
                    if (recs.Count >= 5) break;
                }
                if (bestOpener != null) recs.Add("Open with " + bestOpener + ".");
            }
        }

        // ---- Healing
        sb.AppendLine("## Healing (Holy)");
        sb.AppendLine();
        if (Heals.Count == 0) sb.AppendLine("No heals cast yet.");
        else {
            sb.AppendLine("| Heal | Casts | Normal size | Crit | Overheal | Effective |");
            sb.AppendLine("|---|---|---|---|---|---|");
            foreach (var kv in Heals) {
                var h = kv.Value;
                double normal = h.NonCritN > 0 ? h.NonCritSum / h.NonCritN : 0;
                double overPct = h.Total > 0 ? h.Over / h.Total : 0;
                sb.AppendLine("| " + kv.Key + " | " + h.Hits + " | " + F0(normal) + " | " + Pct(h.Hits > 0 ? (double)h.Crits / h.Hits : 0)
                    + " | " + Pct(overPct) + " | " + F0(h.Total - h.Over) + " |");
                if (h.Hits >= 3 && overPct > 0.3)
                    recs.Add(kv.Key + " overhealed " + Pct(overPct) + ": wait until you're missing at least " + F0(normal) + " health (Flow's blue heal suggestion does this).");
            }
        }
        sb.AppendLine();

        // ---- Tanking / survival
        sb.AppendLine("## Tanking and survival (Protection)");
        sb.AppendLine();
        int swings = 0, dodge = 0, parry = 0, block = 0, miss = 0;
        foreach (var f in Fights) { swings += f.Swings; dodge += f.Dodges; parry += f.Parries; block += f.Blocks; miss += f.Misses; }
        if (swings > 0)
            sb.AppendLine("Melee swings at you: " + swings + ". Dodged " + Pct((double)dodge / swings) + ", parried "
                + Pct((double)parry / swings) + ", blocked " + Pct((double)block / swings) + ", missed " + Pct((double)miss / swings) + ".");
        sb.AppendLine();
        sb.AppendLine("Threat isn't written to the combat log, so threat per second comes from Flow's in-game sampling instead (`/flow fights` when tanking).");
        sb.AppendLine();
        sb.AppendLine("### How hard mobs hit you");
        sb.AppendLine();
        sb.AppendLine("| Mob | Damage per second | Fights |");
        sb.AppendLine("|---|---|---|");
        foreach (var kv in MobDps()) sb.AppendLine("| " + kv.Key + " | " + F1(kv.Value[0]) + " | " + F0(kv.Value[1]) + " |");
        sb.AppendLine();
        if (deaths > 0) recs.Add("You died " + deaths + " time(s). Check the mobs above that hit hardest and heal earlier against them.");

        sb.AppendLine("## Recommendations");
        sb.AppendLine();
        if (recs.Count == 0) sb.AppendLine("- Nothing stands out yet. More fights make this sharper.");
        foreach (var r in recs) sb.AppendLine("- [ ] " + r);
        sb.AppendLine();
        sb.AppendLine("These are patterns in your own fights, not proof: harder mobs give lower DPS whatever you press. Flow only uses them to choose between spells marked as interchangeable.");
        return sb.ToString();
    }

    // name -> { dps, fights }
    public Dictionary<string, double[]> MobDps() {
        var sum = new Dictionary<string, double[]>();
        foreach (var f in Fights) {
            foreach (var kv in f.TakenBySource) {
                double[] v;
                if (!sum.TryGetValue(kv.Key, out v)) { v = new double[3]; sum[kv.Key] = v; }
                v[0] += kv.Value; v[1] += f.Duration; v[2] += 1;
            }
        }
        var outd = new Dictionary<string, double[]>();
        foreach (var kv in sum) outd[kv.Key] = new[] { kv.Value[0] / kv.Value[1], kv.Value[2] };
        return outd;
    }

    static string Lua(string s) { return "\"" + s.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\""; }

    public string LearnedLua(string date) {
        var sb = new StringBuilder();
        sb.AppendLine("-- GENERATED by tools/analyze-combatlog.ps1 on " + date + ". Do not edit by hand:");
        sb.AppendLine("-- re-run the script instead. Learned from " + Fights.Count + " fights in your combat log files.");
        sb.AppendLine("local _, ns = ...");
        sb.AppendLine("ns:Register(\"learned\", \"combatlog\", {");
        sb.AppendLine("    generated = " + Lua(date) + ",");
        sb.AppendLine("    fights = " + Fights.Count + ",");
        sb.AppendLine("    -- Spell order bias per role and fight type (-1..1), from best vs worst fights.");
        sb.AppendLine("    bias = { dps = {");
        foreach (var type in new[] { "normal", "aoe", "boss", "all" }) {
            var l = Usable(type);
            if (l.Count < 6) continue;
            List<Fight> top, bottom;
            var diffs = Compare(l, out top, out bottom);
            sb.Append("        " + type + " = { ");
            foreach (var d in diffs) sb.Append("[" + Lua(d.Spell) + "] = " + d.Bias.ToString("0.00", CultureInfo.InvariantCulture) + ", ");
            sb.AppendLine("},");
        }
        sb.AppendLine("    } },");
        sb.AppendLine("    -- Normal (non-crit) heal size per spell.");
        sb.AppendLine("    heals = {");
        foreach (var kv in Heals)
            if (kv.Value.NonCritN >= 3)
                sb.AppendLine("        [" + Lua(kv.Key) + "] = " + F0(kv.Value.NonCritSum / kv.Value.NonCritN) + ",");
        sb.AppendLine("    },");
        sb.AppendLine("    -- Damage per second each mob deals to you.");
        sb.AppendLine("    mobs = {");
        foreach (var kv in MobDps())
            if (kv.Value[1] >= 2)
                sb.AppendLine("        [" + Lua(kv.Key) + "] = " + F1(kv.Value[0]) + ",");
        sb.AppendLine("    },");
        sb.AppendLine("})");
        return sb.ToString();
    }
}
}
'@

if (-not ('FlowLog.Analyzer' -as [type])) { Add-Type -TypeDefinition $source -Language CSharp }

if (-not $Files) {
    $Files = @(Get-ChildItem $LogDir -Filter 'WoWCombatLog*.txt' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime | ForEach-Object FullName)
}
if (-not $Files -or $Files.Count -eq 0) {
    Write-Host "No combat log files in $LogDir. In game: /flow log auto (or /combatlog), play a while, then run this again."
    exit 1
}

$a = New-Object FlowLog.Analyzer
$a.MinFight = $MinFightSeconds
foreach ($f in $Files) { Write-Host "Reading $f"; $a.ReadFile($f) }
$a.Finish()

$stamp = Get-Date -Format 'yyyy-MM-dd HHmm'
$utf8 = New-Object System.Text.UTF8Encoding $false
New-Item -ItemType Directory -Force $ReportDir | Out-Null
$reportPath = Join-Path $ReportDir "Combat Report $stamp.md"
[IO.File]::WriteAllText($reportPath, $a.Report($stamp), $utf8)
$learnedPath = [IO.Path]::GetFullPath($LearnedOut)
New-Item -ItemType Directory -Force (Split-Path $learnedPath) | Out-Null
[IO.File]::WriteAllText($learnedPath, $a.LearnedLua($stamp), $utf8)

Write-Host ("{0} fights from {1} lines. Report: {2}" -f $a.Fights.Count, $a.Lines, $reportPath)
Write-Host "Learned data for Flow: $learnedPath  (/reload in game to use it)"
if ($a.AdvancedSeen) { Write-Host "Note: Advanced Combat Logging is on; parsed anyway, but turning it off makes logs smaller." }
