using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using Grpc.Core;
using Grpc.Core.Interceptors;

namespace cartservice.interceptors
{
    public class JwtLoggingInterceptor : Interceptor
    {
        private bool IsCompressionEnabled => 
            Environment.GetEnvironmentVariable("ENABLE_JWT_COMPRESSION") == "true";

        public override async Task<TResponse> UnaryServerHandler<TRequest, TResponse>(
            TRequest request,
            ServerCallContext context,
            UnaryServerMethod<TRequest, TResponse> continuation)
        {
            string jwt = null;
            bool wasCompressed = false;

            // Check for compressed JWT headers (x-jwt-*)
            var staticHeader = context.RequestHeaders.FirstOrDefault(h => h.Key == "x-jwt-static");
            if (staticHeader != null)
            {
                // Compressed format detected - reassemble JWT
                var sessionHeader = context.RequestHeaders.First(h => h.Key == "x-jwt-session");
                var dynamicHeader = context.RequestHeaders.First(h => h.Key == "x-jwt-dynamic");
                var sigHeader = context.RequestHeaders.First(h => h.Key == "x-jwt-sig");

                jwt = ReassembleJWT(staticHeader.Value, sessionHeader.Value, dynamicHeader.Value, sigHeader.Value);
                wasCompressed = true;

                int totalSize = staticHeader.Value.Length + sessionHeader.Value.Length + dynamicHeader.Value.Length + sigHeader.Value.Length;
                Console.WriteLine($"[JWT-FLOW] Cart Service ← Frontend/Checkout: Received compressed JWT ({totalSize} bytes) via {context.Method}");
                Console.WriteLine($"[JWT-COMPRESSION] Component sizes - Static: {staticHeader.Value.Length}b, Session: {sessionHeader.Value.Length}b, Dynamic: {dynamicHeader.Value.Length}b, Sig: {sigHeader.Value.Length}b");
            }
            else
            {
                // Standard format: "Bearer <token>"
                var authHeader = context.RequestHeaders.FirstOrDefault(h => h.Key == "authorization");
                if (authHeader != null)
                {
                    jwt = authHeader.Value.Replace("Bearer ", "");
                    Console.WriteLine($"[JWT-FLOW] Cart Service ← Frontend/Checkout: Received full JWT ({jwt.Length} bytes) via {context.Method}");
                }
            }

            // Log JWT reception (debug)
            if (jwt != null)
            {
                Console.WriteLine($"[JWT-DEBUG] JWT preview: {jwt.Substring(0, Math.Min(50, jwt.Length))}...");
            }
            else
            {
                Console.WriteLine($"[JWT-FLOW] Cart Service: No JWT received in {context.Method}");
            }

            return await continuation(request, context);
        }

        private string ReassembleJWT(string staticJson, string sessionJson, string dynamicJson, string signature)
        {
            try
            {
                // Configure JsonSerializerOptions for .NET 9.0 AOT compatibility
                var options = new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true,
                    WriteIndented = false
                };

                // Parse JSON components
                var staticObj = JsonDocument.Parse(staticJson).RootElement;
                var sessionObj = JsonDocument.Parse(sessionJson).RootElement;
                var dynamicObj = JsonDocument.Parse(dynamicJson).RootElement;

                // Rebuild header using string concatenation to avoid reflection
                var alg = staticObj.GetProperty("alg").GetString();
                var typ = staticObj.GetProperty("typ").GetString();
                string headerJson = $"{{\"alg\":\"{alg}\",\"typ\":\"{typ}\"}}";

                // Rebuild payload by merging all claims using string builder
                var payloadParts = new List<string>();

                // Add static claims (except alg and typ which go in header)
                foreach (var prop in staticObj.EnumerateObject())
                {
                    if (prop.Name != "alg" && prop.Name != "typ")
                    {
                        payloadParts.Add(FormatJsonProperty(prop.Name, prop.Value));
                    }
                }

                // Add session claims
                foreach (var prop in sessionObj.EnumerateObject())
                {
                    payloadParts.Add(FormatJsonProperty(prop.Name, prop.Value));
                }

                // Add dynamic claims
                foreach (var prop in dynamicObj.EnumerateObject())
                {
                    payloadParts.Add(FormatJsonProperty(prop.Name, prop.Value));
                }

                // Build payload JSON
                string payloadJson = "{" + string.Join(",", payloadParts) + "}";

                // Base64Url encode
                string headerB64 = Base64UrlEncode(Encoding.UTF8.GetBytes(headerJson));
                string payloadB64 = Base64UrlEncode(Encoding.UTF8.GetBytes(payloadJson));

                // Reconstruct JWT
                string jwt = $"{headerB64}.{payloadB64}.{signature}";
                Console.WriteLine($"[JWT-COMPRESSION] JWT reassembled from compressed headers ({jwt.Length} bytes)");
                Console.WriteLine($"[JWT-COMPRESSION] Component sizes - Static: {staticJson.Length}b, Session: {sessionJson.Length}b, Dynamic: {dynamicJson.Length}b, Sig: {signature.Length}b");
                
                return jwt;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[JWT-COMPRESSION] Failed to reassemble JWT: {ex.Message}");
                return null;
            }
        }

        private string FormatJsonProperty(string name, JsonElement value)
        {
            switch (value.ValueKind)
            {
                case JsonValueKind.String:
                    return $"\"{name}\":\"{value.GetString()}\"";
                case JsonValueKind.Number:
                    return $"\"{name}\":{value.GetRawText()}";
                case JsonValueKind.True:
                    return $"\"{name}\":true";
                case JsonValueKind.False:
                    return $"\"{name}\":false";
                case JsonValueKind.Null:
                    return $"\"{name}\":null";
                default:
                    return $"\"{name}\":{value.GetRawText()}";
            }
        }

        private string Base64UrlEncode(byte[] input)
        {
            string base64 = Convert.ToBase64String(input);
            // Convert to Base64Url format (remove padding and replace characters)
            return base64.TrimEnd('=').Replace('+', '-').Replace('/', '_');
        }
    }
}
