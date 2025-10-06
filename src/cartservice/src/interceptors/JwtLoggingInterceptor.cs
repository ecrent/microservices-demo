using System;
using System.Linq;
using System.Threading.Tasks;
using Grpc.Core;
using Grpc.Core.Interceptors;

namespace cartservice.interceptors
{
    public class JwtLoggingInterceptor : Interceptor
    {
        public override async Task<TResponse> UnaryServerHandler<TRequest, TResponse>(
            TRequest request,
            ServerCallContext context,
            UnaryServerMethod<TRequest, TResponse> continuation)
        {
            // Log JWT if present in metadata
            var authHeader = context.RequestHeaders.FirstOrDefault(h => h.Key == "authorization");
            if (authHeader != null)
            {
                Console.WriteLine($"[JWT] Received JWT in {context.Method}: {authHeader.Value.Substring(0, Math.Min(50, authHeader.Value.Length))}...");
            }
            else
            {
                Console.WriteLine($"[JWT] No JWT received in {context.Method}");
            }

            return await continuation(request, context);
        }
    }
}
