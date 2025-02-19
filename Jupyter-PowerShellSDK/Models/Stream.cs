﻿using Newtonsoft.Json;

namespace Jupyter_PowerShellSDK.Models
{
    public class Stream
    {
        public const string StdOut = "stdout";
        public const string StdErr = "stderr";
        
        [JsonProperty("name")] public string Name { get; set; }

        [JsonProperty("text")] public string Text { get; set; }
    }
}