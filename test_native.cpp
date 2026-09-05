// 本地测试 harness：验证 verify.cpp 导出函数的实际输出
#include <cstdio>
#include <cstring>

// 直接引入被测函数（从 verify.cpp 提取同一段实现）
extern "C" {
  const char* domain_pool();
  const char* embedded_token();
}

int main() {
  printf("domain_pool=[%s]\n", domain_pool());
  const char* t = embedded_token();
  printf("embedded_token_len=%zu\n", strlen(t));
  printf("embedded_token=[%s]\n", t);
  return 0;
}