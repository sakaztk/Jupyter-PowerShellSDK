using Newtonsoft.Json;
using Newtonsoft.Json.Serialization;

namespace Jupyter_PowerShellSDK.Models
{
    public class Status
    {
        public const string Busy = "busy";
        public const string Idle = "idle";
        public const string Starting = "starting";
        
        [JsonProperty("execution_state")]
        public string ExecutionState { get; set; }
    }
}