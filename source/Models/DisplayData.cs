using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace Jupyter_PowerShellSDK.Models
{
    public class DisplayData
    {
        [JsonProperty("data")] public JObject Data { get; set; } = new JObject();
        
        [JsonProperty("metadata")] public JObject MetaData { get; set; } = new JObject();
        
        [JsonProperty("transient")] public JObject Transient { get; set; } = new JObject();
    }
}