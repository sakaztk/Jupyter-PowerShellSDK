using Newtonsoft.Json;

namespace Jupyter_PowerShell5.Models
{
    public class LanguageInfo
    {
        [JsonProperty("name")] public string Name { get; set; }

        [JsonProperty("version")] public string Version { get; set; }

        [JsonProperty("mimetype")] public string MimeType { get; set; }

        [JsonProperty("file_extension")] public string FileExtension { get; set; }

        [JsonProperty("pygments_lexer")] public string PygmentsLexer { get; set; }

        [JsonProperty("codemirror_mode")] public string CodemirrorMode { get; set; }

        [JsonProperty("nbconvert_exporter")] public string NbconvertExporter { get; set; }
    }
}