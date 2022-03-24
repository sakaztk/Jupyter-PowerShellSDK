using System.Collections.Generic;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace Jupyter_PowerShell5.Models
{
    public class Message
    {
        [JsonIgnore] public List<byte[]> Identities { get; set; } = new List<byte[]>();

        [JsonIgnore] public string Signature { get; set; }

        [JsonProperty("header")] public Header Header { get; set; }

        [JsonProperty("parent_header")] public Header ParentHeader { get; set; } = new Header();

        [JsonProperty("metadata")] public JObject MetaData { get; set; } = new JObject();

        [JsonProperty("content")] public JObject Content { get; set; } = new JObject();

        [JsonProperty("buffers")] public List<byte[]> Buffers { get; set; } = new List<byte[]>();

        public static Message Create(string session, string messageType, object content)
        {
            return new Message
            {
                Header = Header.Create(session, messageType),
                Content = JObject.FromObject(content)
            };
        }

        public static Message Create(Message parentMessage, string messageType, object content)
        {
            return new Message
            {
                Identities = parentMessage.Identities,
                Header = Header.Create(parentMessage.Header.Session, messageType),
                ParentHeader = parentMessage.Header,
                Content = JObject.FromObject(content)
            };
        }
    }
}