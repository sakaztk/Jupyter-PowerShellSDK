using Newtonsoft.Json;

namespace Jupyter_PowerShell5.Models
{
    public abstract class ReplyStatusBase
    {
        public const string Ok = "ok";
        public const string Error = "error";
        public const string Aborted = "aborted";

        [JsonProperty("status")] public string Status { get; set; } = Ok;
    }
}