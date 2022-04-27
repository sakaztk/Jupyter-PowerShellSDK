using System.Collections.Generic;
using Newtonsoft.Json;

namespace Jupyter_PowerShellSDK.Models
{
    public class ExecuteReplyOk : ExecuteReplyBase
    {
        [JsonProperty("user_expressions")] public Dictionary<string, string> UserExpressions { get; set; }
    }
}