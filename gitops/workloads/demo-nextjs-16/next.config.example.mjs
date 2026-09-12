/** @type {import('next').NextConfig} */
const nextConfig = {
  // BẮT BUỘC để chạy trên Kubernetes / Docker:
  // Next.js sẽ tự động phân tích và gom tất cả node_modules cần thiết vào folder .next/standalone
  output: 'standalone',

  // Tùy chọn tối ưu cho containerized environment
  poweredByHeader: false,
  reactStrictMode: true,
};

export default nextConfig;
