using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using PeanutButter.INI;

namespace PalServerConfigManager
{
    public class PalWorldSettings
    {
        public const string DefaultSettingsFileRelativePath = "DefaultPalWorldSettings.ini";
        public static readonly string SettingsFileRelativePath = Path.Combine("Pal", "Saved", "Config", "LinuxServer", "PalWorldSettings.ini");

        const string SettingsSectionName = "/Script/Pal.PalGameWorldSettings";
        const string SettingsKey = "OptionSettings";

        private Dictionary<string, string> settingsValues = new();

        static public PalWorldSettings FromFile(string filePath)
        {
            if (!File.Exists(filePath))
            {
                throw new FileNotFoundException($"File doesn't exist: {filePath}");
            }

            var fileText = File.ReadAllText(filePath);

            INIFile ini;
            try
            {
                // Unreal's INI file format isn't *exactly* to spec.
                // (Their format can add, remove, mutate keys ... it's weird.)
                // But in Palworld's case, the file SHOULD be simple enough
                // that it's compatible with common INI parsers.
                //
                // ... but avoid using the INI parser's internal file i/o,
                // so that a hopeful future UnrealINI parsing library
                // can easily slot in here instead.
                ini = INIFile.FromString(fileText);
            }
            catch (Exception ex)
            {
                throw new InvalidDataException($"Failed to parse INI file: {filePath}", ex);
            }

            IDictionary<string, string> settingsSection;
            try
            {
                settingsSection = ini.GetSection(SettingsSectionName);
            }
            catch (Exception ex)
            {
                throw new InvalidDataException($"No '{SettingsSectionName}' section in INI file: {filePath}", ex);
            }

            // Palworld keeps all of its settings in a structure
            // within this single INI file/section key.
            string settingsString;
            if (!settingsSection.TryGetValue(SettingsKey, out settingsString))
            {
                throw new InvalidDataException($"No '{SettingsKey}' in the '{SettingsSectionName}' section of INI file: {filePath}");
            }

            // The schema of this settings object/structure is,
            // per Unreal, non-standard and weird.
            // (It looks kinda like JSON, but with parens surrounding
            // objects AND lists. How do you tell them apart!?)
            //
            // We're not going to try too hard to understand all of it;
            // aside from detecting a top-level object's keys and values,
            // treat everything like a simple string.
            // (In other words, ignore lists or objects nested inside.)
            if (!settingsString.StartsWith('(') || !settingsString.EndsWith(')'))
            {
                throw new InvalidDataException($"Contents of '{SettingsKey}' have an unexpected format (no parens) in INI file: {filePath}");
            }

            var settingsValues = new Dictionary<string, string>();
            for (var keyStartPos = 1; keyStartPos < (settingsString.Length - 1); ++keyStartPos)
            {
                var keyEndPos = settingsString.IndexOf('=', keyStartPos);
                if (keyEndPos == -1)
                {
                    throw new InvalidDataException($"Invalid settings (missing '=' after position {keyStartPos}) in INI file: {filePath}");
                }

                var settingKey = settingsString.Substring(keyStartPos, keyEndPos - keyStartPos).Trim();

                var valueStartPos = keyEndPos + 1;
                while (Char.IsWhiteSpace(settingsString[valueStartPos]))
                {
                    ++valueStartPos;
                }

                var valueEndPos = valueStartPos;
                if (settingsString[valueStartPos] == '\'' || settingsString[valueStartPos] == '"')
                {
                    // Is the value is wrapped in single- or double-quote marks?
                    var quoteMark = settingsString[valueStartPos];
                    valueEndPos = settingsString.IndexOf(quoteMark, valueEndPos + 1);

                    // (Avoid backslash-escaped quote marks, though.)
                    while (settingsString[valueEndPos - 1] == '\\')
                    {
                        valueEndPos = settingsString.IndexOf(quoteMark, valueEndPos + 1);
                    }
                }
                else if (settingsString[valueStartPos] == '(')
                {
                    // Is the value wrapped in parentheses?
                    valueEndPos = settingsString.IndexOf(')', valueEndPos + 1);

                    // (Avoid backslash-escaped parens, though.)
                    while (settingsString[valueEndPos - 1] == '\\')
                    {
                        valueEndPos = settingsString.IndexOf(')', valueEndPos + 1);
                    }
                }

                // Find the next ',' _or_ the end of the settings string.
                var nextComma = settingsString.IndexOf(',', valueEndPos);
                if (nextComma != -1)
                {
                    valueEndPos = nextComma;
                }
                else
                {
                    valueEndPos = settingsString.Length - 1;
                }

                var settingValue = settingsString.Substring(valueStartPos, valueEndPos - valueStartPos).Trim();
                settingsValues.Add(settingKey, settingValue);

                keyStartPos = valueEndPos;
            }

            return new PalWorldSettings()
            {
                settingsValues = settingsValues,
            };
        }

        public void WriteToFile(string filePath)
        {
            var settingsStringBuilder = new StringBuilder();
            settingsStringBuilder.Append('(');
            var serializedSettingsCount = 0;
            foreach (var setting in this.settingsValues)
            {
                settingsStringBuilder.Append(setting.Key);
                settingsStringBuilder.Append('=');
                settingsStringBuilder.Append(setting.Value);

                ++serializedSettingsCount;
                if (serializedSettingsCount < this.settingsValues.Count)
                {
                    settingsStringBuilder.Append(',');
                }
            }
            settingsStringBuilder.Append(')');

            var settingsString = settingsStringBuilder.ToString();

            // DON'T use a conventional INI-file serializer,
            // because it may try to escape strings in a way that
            // Unreal's weird INI format doesn't actually want!
            var fileTextBuilder = new StringBuilder();
            fileTextBuilder.Append('[');
            fileTextBuilder.Append(SettingsSectionName);
            fileTextBuilder.Append(']');
            fileTextBuilder.AppendLine();
            fileTextBuilder.Append(SettingsKey);
            fileTextBuilder.Append('=');
            fileTextBuilder.Append(settingsString);
            fileTextBuilder.AppendLine();

            var fileText = fileTextBuilder.ToString();
            File.WriteAllText(filePath, fileText);
        }

        public bool TryGetValue(string settingKey, out string settingValue)
        {
            return this.settingsValues.TryGetValue(settingKey, out settingValue);
        }

        public void SetValue(string settingKey, string settingValue)
        {
            this.settingsValues[settingKey] = settingValue;
        }

        static public string StringValueWithEnclosingQuotes(string stringValue)
        {
            if (stringValue.StartsWith('"') && stringValue.EndsWith('"'))
            {
                return stringValue;
            }

            var quoteEscapedStringValue = stringValue.Replace("\"", "\\\"");
            return $"\"{quoteEscapedStringValue}\"";
        }
    }
}
