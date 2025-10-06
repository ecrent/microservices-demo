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

                Console.WriteLine($"[JWT-COMPRESSION] Reassembled JWT from compressed headers");
                Console.WriteLine($"[JWT-COMPRESSION] Static: {staticHeader.Value.Length}b, Session: {sessionHeader.Value.Length}b, Dynamic: {dynamicHeader.Value.Length}b, Sig: {sigHeader.Value.Length}b");
            }
            else
            {
                // Standard format: "Bearer <token>"
                var authHeader = context.RequestHeaders.FirstOrDefault(h => h.Key == "authorization");
                if (authHeader != null)
                {
                    jwt = authHeader.Value.Replace("Bearer ", "");
                }
            }

            // Log JWT reception
            if (jwt != null)
            {
                Console.WriteLine($"[JWT] Received JWT in {context.Method}: {jwt.Substring(0, Math.Min(50, jwt.Length))}... (compressed={wasCompressed}, length={jwt.Length}b)");
            }
            else
            {
                Console.WriteLine($"[JWT] No JWT received in {context.Method}");
            }

            return await continuation(request, context);
        }

        private string ReassembleJWT(string staticJson, string sessionJson, string dynamicJson, string signature)
        {
            try
            {
                // Parse JSON components
                var staticObj = JsonDocument.Parse(staticJson).RootElement;
                var sessionObj = JsonDocument.Parse(sessionJson).RootElement;
                var dynamicObj = JsonDocument.Parse(dynamicJson).RootElement;

                // Rebuild header
                var header = new
                {
                    alg = staticObj.GetProperty("alg").GetString(),
                    typ = staticObj.GetProperty("typ").GetString()
                };

                // Rebuild payload by merging all claims
                var payloadDict = new Dictionary<string, object>();

                // Add static claims (except alg and typ which go in header)
                foreach (var prop in staticObj.EnumerateObject())
                {
                    if (prop.Name != "alg" && prop.Name != "typ")
                    {
                        payloadDict[prop.Name] = GetJsonValue(prop.Value);
                    }
                }

                // Add session claims
                foreach (var prop in sessionObj.EnumerateObject())
                {
                    payloadDict[prop.Name] = GetJsonValue(prop.Value);
                }

                // Add dynamic claims
                foreach (var prop in dynamicObj.EnumerateObject())
                {
                    payloadDict[prop.Name] = GetJsonValue(prop.Value);
                }

                // Serialize header and payload
                string headerJson = JsonSerializer.Serialize(header);
                string payloadJson = JsonSerializer.Serialize(payloadDict);

                // Base64Url encode
                string headerB64 = Base64UrlEncode(Encoding.UTF8.GetBytes(headerJson));
                string payloadB64 = Base64UrlEncode(Encoding.UTF8.GetBytes(payloadJson));

                // Reconstruct JWT
                return $"{headerB64}.{payloadB64}.{signature}";
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[JWT-COMPRESSION] Failed to reassemble JWT: {ex.Message}");
                return null;
            }
        }

        private object GetJsonValue(JsonElement element)
        {
            switch (element.ValueKind)
            {
                case JsonValueKind.String:
                    return element.GetString();
                case JsonValueKind.Number:
                    return element.GetInt64();
                case JsonValueKind.True:
                case JsonValueKind.False:
                    return element.GetBoolean();
                case JsonValueKind.Array:
                    return element.EnumerateArray().Select(e => GetJsonValue(e)).ToArray();
                default:
                    return element.ToString();
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
