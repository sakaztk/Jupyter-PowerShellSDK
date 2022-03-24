using System.Linq;
using System.Reflection;
using Jupyter_PowerShell5.Models;

namespace Jupyter_PowerShell5
{
    public static class MessageHandlers
    {
        public static void HandleKernelInfo(Kernel kernel, Message message)
        {
            kernel.ShellSocket.SendMessage(Message.Create(
                message, "kernel_info_reply", new KernelInfoReply
                {
                    Status = ReplyStatusBase.Ok,
                    ProtocolVersion = "5.3",
                    Implementation = "powershell5",
                    ImplementationVersion = "1.0.0",
                    LanguageInfo = new LanguageInfo
                    {
                        Name = "powershell",
                        Version = "5.1.0",
                        MimeType = "application/x-powershell",
                        FileExtension = "ps1",
                        PygmentsLexer = "powershell",
                        CodemirrorMode = "powershell",
                        NbconvertExporter = "script"
                    },
                    Banner = $"Windows PowerShell 5.1 (CLR {Assembly.GetExecutingAssembly().ImageRuntimeVersion})"
                }), kernel);
        }

        public static void HandleExecute(Kernel kernel, Message message)
        {
            var req = message.Content.ToObject<ExecuteRequest>();
            var count = kernel.InvokePowerShell(req.Code, message);
            kernel.ShellSocket.SendMessage(Message.Create(
                message, "execute_result", new ExecuteReplyOk
                {
                    ExecutionCount = count
                }), kernel);
        }

        public static void HandleComplete(Kernel kernel, Message message)
        {
            var req = message.Content.ToObject<CompleteRequest>();
            var result = kernel.InvokeCommandCompletion(req);
            kernel.ShellSocket.SendMessage(Message.Create(
                message, "complete_reply", new CompleteReply
                {
                    Matches = result.CompletionMatches.Select(match => match.CompletionText).ToList(),
                    CursorStart = result.ReplacementIndex,
                    CursorEnd = result.ReplacementIndex + result.ReplacementLength
                }), kernel);
        }
    }
}