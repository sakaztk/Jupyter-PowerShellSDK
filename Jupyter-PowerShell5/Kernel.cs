using System;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Jupyter_PowerShell5.Models;
using NetMQ;
using NetMQ.Sockets;

namespace Jupyter_PowerShell5
{
    public class Kernel
    {
        public delegate void HandleMessage(Kernel kernel, Message message);

        public ResponseSocket HBSocket { get; set; }
        public RouterSocket ShellSocket { get; set; }
        public PublisherSocket IOPubSocket { get; set; }

        private readonly Connection connection;
        private readonly HMAC signatureProvider;
        private Task heartbeatTask;
        private Task serverTask;
        private CancellationTokenSource cancellationTokenSource;
        private Runspace psRunspace;
        private int executionCount;

        public Kernel(Connection connection)
        {
            this.connection = connection;
            if (!string.IsNullOrEmpty(this.connection.Key))
            {
                this.signatureProvider =
                    HMAC.Create(this.connection.SignatureScheme.Replace("-", string.Empty).ToUpperInvariant());
                this.signatureProvider.Key = Encoding.ASCII.GetBytes(this.connection.Key);
            }
        }

        public void Start()
        {
            lock (this)
            {
                this.Stop();
                Console.WriteLine($"Creating PowerShell session");
                this.psRunspace = RunspaceFactory.CreateRunspace(InitialSessionState.CreateDefault());
                this.psRunspace.Open();

                Console.WriteLine("Starting kernel");
                this.cancellationTokenSource = new CancellationTokenSource();
                this.heartbeatTask = Task.Run(this.HeartbeatTask);
                this.serverTask = Task.Run(this.ServerTask);
            }
        }

        public void Wait()
        {
            Task.WaitAll(this.heartbeatTask, this.serverTask);
        }

        public void Stop()
        {
            lock (this)
            {
                if (this.cancellationTokenSource != null && !this.cancellationTokenSource.IsCancellationRequested)
                {
                    Console.WriteLine("Stopping kernel");
                    this.cancellationTokenSource.Cancel();
                    this.Wait();

                    Console.WriteLine("Closing PowerShell session");
                    this.psRunspace.Close();
                    this.psRunspace.Dispose();
                }
            }
        }

        public string SignMessage(params string[] parts)
        {
            this.signatureProvider.Initialize();
            foreach (var item in parts)
            {
                var bytes = Encoding.UTF8.GetBytes(item);
                this.signatureProvider.TransformBlock(bytes, 0, bytes.Length, null, 0);
            }

            this.signatureProvider.TransformFinalBlock(Array.Empty<byte>(), 0, 0);
            return BitConverter.ToString(this.signatureProvider.Hash).Replace("-", string.Empty).ToLowerInvariant();
        }

        public int InvokePowerShell(string script, Message originalMessage)
        {
            using var ps = PowerShell.Create();
            ps.Runspace = this.psRunspace;
            ps.Streams.Verbose.DataAdded += this.GetStreamHandler(index =>
                $"VERBOSE: {ps.Streams.Verbose[index]}", ps, Stream.StdOut, originalMessage);
            ps.Streams.Information.DataAdded += this.GetStreamHandler(index =>
                ps.Streams.Information[index].ToString(), ps, Stream.StdOut, originalMessage);
            ps.Streams.Warning.DataAdded += this.GetStreamHandler(index =>
                $"WARNING: {ps.Streams.Warning[index]}", ps, Stream.StdOut, originalMessage);
            ps.Streams.Error.DataAdded += this.GetStreamHandler(index =>
                ps.Streams.Error[index].ToString(), ps, Stream.StdErr, originalMessage);

            try
            {
                var outputs = ps.AddScript(script).AddCommand("Out-String").AddParameter("Width", 200).Invoke();
                this.IOPubSocket.SendMessage(Message.Create(
                    originalMessage, "stream", new Stream
                    {
                        Name = Stream.StdOut,
                        Text = string.Join("\r\n", outputs)
                    }), this);
            }
            catch (RuntimeException ex)
            {
                this.IOPubSocket.SendMessage(Message.Create(
                    originalMessage, "stream", new Stream
                    {
                        Name = Stream.StdErr,
                        Text = $"{ex.GetType()}: {ex.Message}\r\n{ex.ErrorRecord.ScriptStackTrace}"
                    }), this);
            }

            this.executionCount += 1;
            return this.executionCount;
        }

        public CommandCompletion InvokeCommandCompletion(CompleteRequest req)
        {
            using var ps = PowerShell.Create();
            ps.Runspace = this.psRunspace;
            return CommandCompletion.CompleteInput(req.Code, req.CursorPosition, null, ps);
        }

        private void HeartbeatTask()
        {
            var hbAddress = this.GetAddress(this.connection.HBPort);
            Console.WriteLine($"Starting heartbeat handler at {hbAddress}");
            this.HBSocket = new ResponseSocket(hbAddress);

            while (!this.cancellationTokenSource.IsCancellationRequested)
            {
                this.HBSocket.SendFrame(this.HBSocket.ReceiveFrameBytes());
                Console.WriteLine("~ Heartbeat");
            }

            Console.WriteLine("Stopping heartbeat handler");
            this.HBSocket.Dispose();
        }

        private void ServerTask()
        {
            var shellAddress = this.GetAddress(this.connection.ShellPort);
            var ioAddress = this.GetAddress(this.connection.IOPubPort);
            Console.WriteLine($"Starting shell server at {shellAddress}");
            Console.WriteLine($"Starting iopub publisher at {ioAddress}");
            this.ShellSocket = new RouterSocket(shellAddress);
            this.IOPubSocket = new PublisherSocket(ioAddress);

            var globalSessionId = Guid.NewGuid().ToString();
            this.IOPubSocket.SendMessage(Message.Create(
                globalSessionId, "status", new Status {ExecutionState = Status.Starting}), this);

            while (!this.cancellationTokenSource.IsCancellationRequested)
            {
                var message = this.ShellSocket.ReceiveMessage(this);
                this.IOPubSocket.SendMessage(Message.Create(
                    message, "status", new Status {ExecutionState = Status.Busy}), this);

                if (!string.IsNullOrEmpty(message.Signature))
                {
                    switch (message.Header.MessageType)
                    {
                        case "kernel_info_request":
                            MessageHandlers.HandleKernelInfo(this, message);
                            break;
                        case "execute_request":
                            MessageHandlers.HandleExecute(this, message);
                            break;
                        case "complete_request":
                            MessageHandlers.HandleComplete(this, message);
                            break;
                    }
                }

                this.IOPubSocket.SendMessage(Message.Create(
                    message, "status", new Status {ExecutionState = Status.Idle}), this);
            }

            Console.WriteLine("Stopping shell server");
            this.ShellSocket.Dispose();
            Console.WriteLine("Stopping iopub publisher");
            this.IOPubSocket.Dispose();
        }

        private string GetAddress(int port)
        {
            return $"{this.connection.Transport}://{this.connection.IP}:{port}";
        }

        private EventHandler<DataAddedEventArgs> GetStreamHandler(Func<int, string> mapper,
            PowerShell powerShell, string targetStream, Message originalMessage)
        {
            return (sender, args) =>
            {
                this.IOPubSocket.SendMessage(Message.Create(
                    originalMessage, "stream", new Stream
                    {
                        Name = targetStream,
                        Text = mapper(args.Index) + "\r\n"
                    }), this);
            };
        }
    }
}