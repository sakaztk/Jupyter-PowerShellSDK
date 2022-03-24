using Newtonsoft.Json;

namespace Jupyter_PowerShell5.Models
{
    public abstract class ExecuteReplyBase : ReplyStatusBase
    {
        [JsonProperty("execution_count")] public int ExecutionCount { get; set; }
    }
}