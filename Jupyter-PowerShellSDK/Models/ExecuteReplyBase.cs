using Newtonsoft.Json;

namespace Jupyter_PowerShellSDK.Models
{
    public abstract class ExecuteReplyBase : ReplyStatusBase
    {
        [JsonProperty("execution_count")] public int ExecutionCount { get; set; }
    }
}