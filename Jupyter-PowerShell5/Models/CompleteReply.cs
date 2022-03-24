using System.Collections.Generic;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace Jupyter_PowerShell5.Models
{
    public class CompleteReply : ReplyStatusBase
    {
        [JsonProperty("matches")] public List<string> Matches { get; set; }
        
        [JsonProperty("cursor_start")] public int CursorStart { get; set; }
        
        [JsonProperty("cursor_end")] public int CursorEnd { get; set; }
        
        [JsonProperty("metadata")] public JObject MetaData { get; set; } = new JObject();
    }
}