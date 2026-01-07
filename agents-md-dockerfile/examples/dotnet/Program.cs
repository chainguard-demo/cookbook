using System;
using System.Net;
using System.Net.Sockets;
using System.Text;

class Program
{
    static void Main(string[] args)
    {
        string host = Environment.GetEnvironmentVariable("HOST") ?? "0.0.0.0";
        int port = int.Parse(Environment.GetEnvironmentVariable("PORT") ?? "8080");

        TcpListener listener = new TcpListener(IPAddress.Parse(host), port);
        listener.Start();

        Console.WriteLine($"Server running at http://{host}:{port}/");

        while (true)
        {
            TcpClient client = listener.AcceptTcpClient();
            NetworkStream stream = client.GetStream();

            byte[] buffer = new byte[1024];
            int bytesRead = stream.Read(buffer, 0, buffer.Length);

            string responseBody = "Hello from Chainguard .NET image!\n";
            string response = "HTTP/1.1 200 OK\r\n" +
                            "Content-Type: text/plain\r\n" +
                            $"Content-Length: {responseBody.Length}\r\n" +
                            "\r\n" +
                            responseBody;

            byte[] responseBytes = Encoding.UTF8.GetBytes(response);
            stream.Write(responseBytes, 0, responseBytes.Length);

            client.Close();
        }
    }
}
