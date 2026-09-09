using System.IO;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using PalServerConfigManager;

namespace PalServerConfigManager.Test
{
    [TestClass]
    public class PalServerSettingsTests
    {
        static readonly string TestFilesDirectory = Path.Combine(Directory.GetCurrentDirectory(), "TestFiles");

        [TestMethod]
        public void TestFromFileInvalidPath()
        {
            Assert.ThrowsExactly<FileNotFoundException>(() =>
            {
                _ = PalWorldSettings.FromFile("this-path-does-not-exist.ini");
            });
        }

        [TestMethod]
        public void TestFromFileInvalidBecauseEmpty()
        {
            var filePath = Path.Combine(TestFilesDirectory, "InvalidBecauseEmpty.ini");

            Assert.ThrowsExactly<InvalidDataException>(() =>
            {
                _ = PalWorldSettings.FromFile(filePath);
            });
        }

        [TestMethod]
        public void TestFromFileDefault()
        {
            var filePath = Path.Combine(TestFilesDirectory, PalWorldSettings.DefaultSettingsFileRelativePath);

            var settings = PalWorldSettings.FromFile(filePath);
            Assert.IsNotNull(settings);

            var foundValue = settings.TryGetValue("ServerName", out var settingValue);
            Assert.IsTrue(foundValue);
            Assert.AreEqual("\"Default Palworld Server\"", settingValue);
        }

        [TestMethod]
        public void TestWriteWithNoChanges()
        {
            var filePath = Path.Combine(TestFilesDirectory, PalWorldSettings.DefaultSettingsFileRelativePath);

            var settings = PalWorldSettings.FromFile(filePath);
            Assert.IsNotNull(settings);

            var testFileRelativePath = "test-no-changes.ini";
            settings.WriteToFile(testFileRelativePath);

            var expectedFilePath = Path.Combine(TestFilesDirectory, "ExpectedNoChanges.ini");
            var expectedFileText = File.ReadAllText(expectedFilePath).ReplaceLineEndings().Trim();
            var actualFileText = File.ReadAllText(testFileRelativePath).ReplaceLineEndings().Trim();
            Assert.AreEqual(expectedFileText, actualFileText);
        }

        [TestMethod]
        public void TestWriteWithSomeChanges()
        {
            var filePath = Path.Combine(TestFilesDirectory, PalWorldSettings.DefaultSettingsFileRelativePath);

            var settings = PalWorldSettings.FromFile(filePath);
            Assert.IsNotNull(settings);

            settings.SetValue("ServerName", "\"Just a Test Server\"");

            var testFileRelativePath = "test-some-changes.ini";
            settings.WriteToFile(testFileRelativePath);

            var expectedFilePath = Path.Combine(TestFilesDirectory, "ExpectedSomeChanges.ini");
            var expectedFileText = File.ReadAllText(expectedFilePath).ReplaceLineEndings().Trim();
            var actualFileText = File.ReadAllText(testFileRelativePath).ReplaceLineEndings().Trim();
            Assert.AreEqual(expectedFileText, actualFileText);
        }
    }
}
