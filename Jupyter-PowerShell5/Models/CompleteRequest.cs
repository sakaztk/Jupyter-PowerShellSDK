using Newtonsoft.Json;

namespace Jupyter_PowerShell5.Models
{
    public class CompleteRequest
    {
        [JsonProperty("code")] public string Code { get; set; }
        
        [JsonProperty("cursor_pos")] public int CursorPosition { get; set; }
    }
}