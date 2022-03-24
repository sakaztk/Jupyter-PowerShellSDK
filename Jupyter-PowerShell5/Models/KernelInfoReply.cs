using Newtonsoft.Json;

namespace Jupyter_PowerShell5.Models
{
    public class KernelInfoReply : ReplyStatusBase
    {
        [JsonProperty("protocol_version")] public string ProtocolVersion { get; set; }

        [JsonProperty("implementation")] public string Implementation { get; set; }

        [JsonProperty("implementation_version")]
        public string ImplementationVersion { get; set; }

        [JsonProperty("language_info")] public LanguageInfo LanguageInfo { get; set; }

        [JsonProperty("banner")] public string Banner { get; set; }
    }
}