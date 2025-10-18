# Attribution and Licensing

## Original Work

This project is based on **Google Cloud Platform's microservices-demo**:
- **Repository**: https://github.com/GoogleCloudPlatform/microservices-demo
- **Copyright**: Google LLC
- **License**: Apache License 2.0
- **Original Purpose**: Demonstration of cloud-native microservices architecture and Google Cloud Platform services

## Academic Modifications

This repository has been modified and extended for a **Master's Thesis** research project focusing on:

**Research Topic**: JWT Compression Optimization in Microservices Architectures using HTTP/2 HPACK

**Key Research Contributions**:
1. Implementation of JWT compression using split headers (x-jwt-static, x-jwt-session, x-jwt-dynamic-bin, x-jwt-sig-bin)
2. Comparative performance analysis of compressed vs. uncompressed JWT tokens
3. Network bandwidth optimization through HTTP/2 HPACK caching
4. Load testing methodology for authentication overhead measurement

## Modified Files and Components

### Core Service Modifications
The following services have been modified to support JWT authentication and compression:
- `src/frontend/` - Added JWT middleware and compression logic
- `src/cartservice/` - JWT validation and header processing
- `src/checkoutservice/` - JWT authentication integration
- `src/shippingservice/` - JWT validation
- `src/paymentservice/` - JWT processing
- `src/emailservice/` - JWT integration

### Kubernetes Manifests
All service deployment YAML files have been extended with:
- `ENABLE_JWT_COMPRESSION` environment variable
- JWT-related configuration options

### Testing Infrastructure (New)
All testing scripts and tools are original contributions for this research:
- `enable_jwt_compression.sh`
- `disable_jwt_compression.sh`
- `run-jwt-compression-test.sh`
- `wsl-run-jwt-compression-test.sh`
- `compare-jwt-compression-enhanced.sh`
- `k6-user-journey-test.js`
- `JWT-COMPRESSION-TEST-GUIDE.md`

### Documentation (New)
Research-specific documentation:
- `JWT-COMPRESSION-TEST-GUIDE.md` - Complete testing guide
- `results.md` - Performance analysis results
- `forme.md` - Research notes and findings

## Preserved Original Code

The following aspects of the original codebase remain largely unchanged:
- Core microservices architecture and communication patterns
- gRPC protocol buffer definitions
- Frontend user interface and UX
- Business logic for e-commerce functionality
- Database and caching implementations
- Service mesh and observability configurations

## License Compliance

This derivative work complies with the Apache License 2.0 by:
1. ✅ Including the complete original LICENSE file
2. ✅ Providing this NOTICE file documenting changes
3. ✅ Preserving all original copyright notices
4. ✅ Clearly marking all modified files
5. ✅ Not using Google trademarks or implying endorsement

## Citation

If you use this work in academic research, please cite:

**Original Work**:
```
Google LLC. (2024). microservices-demo: Sample cloud-first application with 10 microservices.
GitHub repository. https://github.com/GoogleCloudPlatform/microservices-demo
```


## Disclaimer

This modified version is provided for academic research purposes. The modifications
and research findings are provided "AS IS" without warranty of any kind, as permitted
under the Apache License 2.0.

The original microservices-demo code is maintained by Google LLC. This derivative
work is not endorsed by or affiliated with Google LLC.

---

*Last Updated: October 18, 2025*
