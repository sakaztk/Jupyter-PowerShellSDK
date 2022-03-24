using System;
using System.IO;
using Jupyter_PowerShellSDK.Models;
using Newtonsoft.Json;

namespace Jupyter_PowerShellSDK
{
    internal class Program
    {
        public static void Main(string[] args)
        {
            if (args.Length > 0)
            {
                Console.WriteLine($"Connection file: {args[0]}");
                var connection = JsonConvert.DeserializeObject<Connection>(File.ReadAllText(args[0]));
                var kernel = new Kernel(connection);
                kernel.Start();
                kernel.Wait();
            }
            else
            {
                Console.WriteLine("Please launch this executable as Jupyter kernel.");
            }
        }
    }
}