using System;
using System.Collections.Generic;
using System.Globalization;
using DOL.Logging;

namespace DOL.GS
{
    /// <summary>
    /// Optional experience rates by level range, read from the server settings
    /// <c>xp_rate_by_level</c> (real players) and <c>bot_xp_rate_by_level</c> (autonomous gamebots).
    /// A setting looks like <c>1-19:3;20-34:5;35-50:12</c>. Inside a listed range its rate
    /// replaces the flat rate (<c>xp_rate</c> or <c>bot_xp_rate</c>); levels outside every range,
    /// an empty setting and an invalid setting all keep the flat rate, so the feature is off by default.
    /// </summary>
    public static class LevelRangeXpRates
    {
        public const double MaximumRate = 1000.0;

        private static readonly Logger Log = LoggerManager.Create(typeof(LevelRangeXpRates));

        /// <summary>One level range and its rate.</summary>
        public readonly record struct LevelRange(int FirstLevel, int LastLevel, double Rate);

        private sealed class Parsed
        {
            public Parsed(string spec, LevelRange[] ranges, string error)
            {
                Spec = spec;
                Ranges = ranges;
                Error = error;
            }

            public string Spec { get; }
            public LevelRange[] Ranges { get; }
            public string Error { get; }
        }

        // One cache entry per setting; settings change rarely, kills happen constantly.
        private static Parsed _playerCache;
        private static Parsed _botCache;

        /// <summary>The rate for a real player character of this level.</summary>
        public static double PlayerRate(int level)
        {
            return EffectiveRate(ServerProperties.Properties.XP_RATE_BY_LEVEL, level, ServerProperties.Properties.XP_RATE,
                ref _playerCache, "xp_rate_by_level");
        }

        /// <summary>The rate for an autonomous gamebot of this level (before the RvR-zone multiplier).</summary>
        public static double BotRate(int level)
        {
            return EffectiveRate(ServerProperties.Properties.BOT_XP_RATE_BY_LEVEL, level, ServerProperties.Properties.BOT_XP_RATE,
                ref _botCache, "bot_xp_rate_by_level");
        }

        /// <summary>
        /// The rate for <paramref name="level"/>: the matching range's rate, or <paramref name="flatRate"/>
        /// when the setting is empty or invalid or no range contains the level.
        /// </summary>
        public static double EffectiveRate(string spec, int level, double flatRate)
        {
            if (string.IsNullOrWhiteSpace(spec))
                return flatRate;
            return TryParse(spec, out LevelRange[] ranges, out _) ? Lookup(ranges, level, flatRate) : flatRate;
        }

        private static double EffectiveRate(string spec, int level, double flatRate, ref Parsed cache, string settingName)
        {
            if (string.IsNullOrWhiteSpace(spec))
                return flatRate;

            Parsed parsed = cache;
            if (parsed == null || !string.Equals(parsed.Spec, spec, StringComparison.Ordinal))
            {
                bool ok = TryParse(spec, out LevelRange[] ranges, out string error);
                parsed = new Parsed(spec, ok ? ranges : null, error);
                cache = parsed;
                // Check the level first, as the rest of the server does: before logging starts
                // (for example in unit tests) the logger has no queue to write to.
                if (ok)
                {
                    if (Log.IsInfoEnabled)
                        Log.Info($"{settingName} in use: {spec}");
                }
                else if (Log.IsWarnEnabled)
                    Log.Warn($"{settingName} is invalid and is ignored ({error}); the flat rate stays in use. Value: \"{spec}\"");
            }

            return parsed.Ranges == null ? flatRate : Lookup(parsed.Ranges, level, flatRate);
        }

        private static double Lookup(LevelRange[] ranges, int level, double flatRate)
        {
            foreach (LevelRange range in ranges)
            {
                if (level >= range.FirstLevel && level <= range.LastLevel)
                    return range.Rate;
            }

            return flatRate;
        }

        /// <summary>
        /// Parses <c>first-last:rate</c> entries separated by semicolons. A single level may be written
        /// without a dash (<c>50:2</c>). Spaces are allowed; the decimal point is always a dot.
        /// Ranges must not overlap; rates must be greater than 0 and at most <see cref="MaximumRate"/>.
        /// </summary>
        public static bool TryParse(string spec, out LevelRange[] ranges, out string error)
        {
            ranges = Array.Empty<LevelRange>();
            error = null;

            if (string.IsNullOrWhiteSpace(spec))
            {
                error = "the setting is empty";
                return false;
            }

            var result = new List<LevelRange>();
            foreach (string rawEntry in spec.Split(';'))
            {
                string entry = rawEntry.Trim();
                if (entry.Length == 0)
                    continue;

                int colon = entry.IndexOf(':');
                if (colon <= 0 || colon != entry.LastIndexOf(':'))
                {
                    error = $"\"{entry}\" is not in the form first-last:rate";
                    return false;
                }

                string levels = entry[..colon].Trim();
                string rateText = entry[(colon + 1)..].Trim();

                int first, last;
                int dash = levels.IndexOf('-');
                if (dash < 0)
                {
                    if (!TryLevel(levels, out first))
                    {
                        error = $"\"{levels}\" is not a level";
                        return false;
                    }

                    last = first;
                }
                else if (!TryLevel(levels[..dash].Trim(), out first) || !TryLevel(levels[(dash + 1)..].Trim(), out last))
                {
                    error = $"\"{levels}\" is not a level range";
                    return false;
                }

                if (last < first)
                {
                    error = $"\"{levels}\" ends before it starts";
                    return false;
                }

                if (!double.TryParse(rateText, NumberStyles.Float, CultureInfo.InvariantCulture, out double rate) ||
                    double.IsNaN(rate) || double.IsInfinity(rate) || rate <= 0 || rate > MaximumRate)
                {
                    error = $"\"{rateText}\" is not a rate above 0 and at most {MaximumRate.ToString(CultureInfo.InvariantCulture)}";
                    return false;
                }

                foreach (LevelRange existing in result)
                {
                    if (first <= existing.LastLevel && last >= existing.FirstLevel)
                    {
                        error = $"{first}-{last} overlaps {existing.FirstLevel}-{existing.LastLevel}";
                        return false;
                    }
                }

                result.Add(new LevelRange(first, last, rate));
            }

            if (result.Count == 0)
            {
                error = "no ranges were given";
                return false;
            }

            ranges = result.ToArray();
            return true;
        }

        private static bool TryLevel(string text, out int level)
        {
            return int.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out level) && level >= 1 && level <= 255;
        }
    }
}
