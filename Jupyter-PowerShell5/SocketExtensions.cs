using System;
using System.Linq;
using System.Text;
using Jupyter_PowerShell5.Models;
using NetMQ;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace Jupyter_PowerShell5
{
    public static class SocketExtensions
    {
        private static readonly byte[] Delimiter = Encoding.ASCII.GetBytes("<IDS|MSG>");

        public static Message ReceiveMessage(this IReceivingSocket socket, Kernel kernel = null)
        {
            var message = new Message();
            while (true)
            {
                var bytes = socket.ReceiveFrameBytes();
                if (bytes.SequenceEqual(Delimiter))
                {
                    break;
                }

                message.Identities.Add(bytes);
            }

            message.Signature = socket.ReceiveFrameString();
            var header = socket.ReceiveFrameString();
            var parentHeader = socket.ReceiveFrameString();
            var metadata = socket.ReceiveFrameString();
            var content = socket.ReceiveFrameString();
            if (kernel != null)
            {
                var sig = kernel.SignMessage(header, parentHeader, metadata, content);
                if (sig != message.Signature)
                {
                    Console.WriteLine("! WARNING: Invalid message signature, ignoring the message");
                    message.Signature = null;
                }
            }

            message.Header = JsonConvert.DeserializeObject<Header>(header);
            message.ParentHeader = JsonConvert.DeserializeObject<Header>(parentHeader);
            message.MetaData = JObject.Parse(metadata);
            message.Content = JObject.Parse(content);
            // Console.WriteLine($"> [{message.Header.MessageType}] {metadata} {content}");
            return message;
        }

        public static void SendMessage(this IOutgoingSocket socket, Message message, Kernel kernel = null)
        {
            var header = JsonConvert.SerializeObject(message.Header);
            var parentHeader = JsonConvert.SerializeObject(message.ParentHeader);
            var metadata = JsonConvert.SerializeObject(message.MetaData);
            var content = JsonConvert.SerializeObject(message.Content);

            if (string.IsNullOrEmpty(message.Signature) && kernel != null)
            {
                message.Signature = kernel.SignMessage(header, parentHeader, metadata, content);
            }

            // Console.WriteLine($"< [{message.Header.MessageType}] {metadata} {content}");
            foreach (var identity in message.Identities)
            {
                socket.SendFrame(identity, true);
            }

            socket.SendFrame(Delimiter, true);
            socket.SendFrame(message.Signature, true);
            socket.SendFrame(header, true);
            socket.SendFrame(parentHeader, true);
            socket.SendFrame(metadata, true);
            socket.SendFrame(content);
        }
    }
}