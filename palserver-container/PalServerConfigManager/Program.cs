using System;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using Microsoft.Extensions.Logging;
using Mono.Options;
using PeanutButter.INI;

namespace PalServerConfigManager
{
    internal sealed class Program
    {
        const string SettingLabel_ServerName = "ServerName";
        const string SettingLabel_ServerDescription = "ServerDescription";

        const string SettingLabel_AdminPassword = "AdminPassword";
        const string SettingLabel_ServerPassword = "ServerPassword";

        const string SettingLabel_RestApiEnabled = "RESTAPIEnabled";

        static bool SetStringValueIfChanged(ILogger logger, PalWorldSettings settings, string settingLabel, string setValue)
        {
            var didChange = false;

            if (!string.IsNullOrEmpty(setValue))
            {
                setValue = PalWorldSettings.StringValueWithEnclosingQuotes(setValue);

                if (!settings.TryGetValue(settingLabel, out var existingValue) || !setValue.Equals(existingValue, StringComparison.Ordinal))
                {
                    logger.LogInformation($"Setting {settingLabel}: {setValue}");
                    didChange = true;
                    settings.SetValue(settingLabel, setValue);
                }
            }

            return didChange;
        }

        static int Main(string[] args)
        {
            using var loggerFactory = LoggerFactory.Create(c => c.AddSystemdConsole());
            var logger = loggerFactory.CreateLogger<Program>();

            var printHelp = false;

            var palServerInstallDir = string.Empty;

            var setServerName = string.Empty;
            var setServerDescription = string.Empty;

            var setAdminPassword = string.Empty;
            var setAdminPasswordFile = string.Empty;
            var setServerPassword = string.Empty;
            var setServerPasswordFile = string.Empty;

            var setRestApiEnabledString = true.ToString();

            var options = new OptionSet()
            {
                { "help", "Print help text", _ => printHelp = true },

                { "palserver-install-dir=", "Path to the PalServer installation directory", o => palServerInstallDir = o },

                { "set-server-name=", $"Set {SettingLabel_ServerName} (cannot be empty)", o => setServerName = o },
                { "set-server-description=", $"Set {SettingLabel_ServerDescription} (cannot be empty)", o => setServerDescription = o },

                { "set-admin-password=", $"Set {SettingLabel_AdminPassword} (cannot be empty)", o => setAdminPassword = o },
                { "set-admin-password-file=", $"Path to a file for setting {SettingLabel_AdminPassword}", o => setAdminPasswordFile = o },
                { "set-server-password=", $"Set {SettingLabel_ServerPassword} (cannot be empty)", o => setServerPassword = o },
                { "set-server-password-file=", $"Path to a file for setting {SettingLabel_ServerPassword}", o => setServerPasswordFile = o },

                { "set-rest-api-enabled=", $"Set {SettingLabel_RestApiEnabled}, default: {setRestApiEnabledString}", o => setRestApiEnabledString = o },
            };
            var unexpectedArgs = options.Parse(args);
            if (unexpectedArgs.Count > 0)
            {
                var unexpectedArgsString = string.Join(' ', unexpectedArgs);
                throw new ArgumentException($"Unexpected arguments: {unexpectedArgsString}");
            }

            if (printHelp)
            {
                options.WriteOptionDescriptions(Console.Out);
                return 0;
            }

            if (string.IsNullOrEmpty(palServerInstallDir))
            {
                throw new ArgumentException("Missing required argument palserver-install-dir");
            }
            // Ensure that the install-dir path is valid, by checking for a default settings file in it.
            var defaultSettingsPath = Path.Combine(palServerInstallDir, PalWorldSettings.DefaultSettingsFileRelativePath);
            if (!File.Exists(defaultSettingsPath))
            {
                throw new ArgumentException($"Invalid palserver-install-dir, missing expected file: {defaultSettingsPath}");
            }

            if (!string.IsNullOrEmpty(setAdminPassword) && !string.IsNullOrEmpty(setAdminPasswordFile))
            {
                throw new ArgumentException($"Cannot specify both set-admin-password and set-admin-password-file");
            }
            if (!string.IsNullOrEmpty(setAdminPasswordFile))
            {
                logger.LogInformation($"Reading {SettingLabel_AdminPassword} from file: {setAdminPasswordFile}");
                setAdminPassword = File.ReadAllText(setAdminPasswordFile).Trim();
            }
            if (!string.IsNullOrEmpty(setServerPassword) && !string.IsNullOrEmpty(setServerPasswordFile))
            {
                throw new ArgumentException($"Cannot specify both set-server-password and set-server-password-file");
            }
            if (!string.IsNullOrEmpty(setServerPasswordFile))
            {
                logger.LogInformation($"Reading {SettingLabel_ServerPassword} from file: {setServerPasswordFile}");
                setServerPassword = File.ReadAllText(setServerPasswordFile).Trim();
            }

            bool setRestApiEnabled;
            if (!bool.TryParse(setRestApiEnabledString, out setRestApiEnabled))
            {
                throw new ArgumentException($"Failed to parse bool from set-rest-api-enabled");
            }

            var settingsPath = Path.Combine(palServerInstallDir, PalWorldSettings.SettingsFileRelativePath);
            var settingsHaveChanged = false;
            PalWorldSettings settings;
            try
            {
                settings = PalWorldSettings.FromFile(settingsPath);
            }
            catch (FileNotFoundException)
            {
                logger.LogInformation($"No settings file found at {settingsPath}, will write with default settings");
                settingsHaveChanged = true;
                settings = PalWorldSettings.FromFile(defaultSettingsPath);
            }
            catch (Exception ex)
            {
                logger.LogError($"Invalid settings file found at {settingsPath}, will re-write with default settings", ex);
                settingsHaveChanged = true;
                settings = PalWorldSettings.FromFile(defaultSettingsPath);
            }

            if (SetStringValueIfChanged(logger, settings, SettingLabel_ServerName, setServerName))
            {
                settingsHaveChanged = true;
            }
            if (SetStringValueIfChanged(logger, settings, SettingLabel_ServerDescription, setServerDescription))
            {
                settingsHaveChanged = true;
            }

            if (SetStringValueIfChanged(logger, settings, SettingLabel_AdminPassword, setAdminPassword))
            {
                settingsHaveChanged = true;
            }
            if (SetStringValueIfChanged(logger, settings, SettingLabel_ServerPassword, setServerPassword))
            {
                settingsHaveChanged = true;
            }

            if (!settings.TryGetValue(SettingLabel_RestApiEnabled, out var restApiEnabled) || setRestApiEnabled != bool.Parse(restApiEnabled))
            {
                logger.LogInformation($"Setting {SettingLabel_RestApiEnabled}: {setRestApiEnabled}");
                settingsHaveChanged = true;
                settings.SetValue(SettingLabel_RestApiEnabled, setRestApiEnabled.ToString());
            }

            if (settingsHaveChanged)
            {
                logger.LogInformation($"Writing settings: {settingsPath}");

                var settingsDir = Path.GetDirectoryName(settingsPath);
                if (!Directory.Exists(settingsDir))
                {
                    Directory.CreateDirectory(settingsDir);
                }

                settings.WriteToFile(settingsPath);
            }
            else
            {
                logger.LogInformation("No settings have changed, exiting");
            }

            return 0;
        }
    }
}
