// Minimal end-to-end smoke test: create an rcl publisher and subscription
// (in the same process) on the compiled-in RMW implementation, publish a
// builtin_interfaces/msg/Time message, and confirm it is received via
// rcl_wait + rcl_take. Exits non-zero on any failure.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "rcl/rcl.h"
#include "rcl/error_handling.h"
#include "builtin_interfaces/msg/time.h"
#include "rosidl_runtime_c/message_type_support_struct.h"

#define CHECK_RCL(stmt) \
  do { \
    rcl_ret_t __ret = (stmt); \
    if (__ret != RCL_RET_OK) { \
      fprintf(stderr, "FAIL: %s -> %s\n", #stmt, rcl_get_error_string().str); \
      rcl_reset_error(); \
      return 1; \
    } \
  } while (0)

int main(int argc, char ** argv)
{
  rcl_ret_t ret;

  rcl_init_options_t init_options = rcl_get_zero_initialized_init_options();
  CHECK_RCL(rcl_init_options_init(&init_options, rcl_get_default_allocator()));

  rcl_context_t context = rcl_get_zero_initialized_context();
  CHECK_RCL(rcl_init(argc, (char const * const *)argv, &init_options, &context));

  rcl_node_t node = rcl_get_zero_initialized_node();
  rcl_node_options_t node_options = rcl_node_get_default_options();
  CHECK_RCL(rcl_node_init(&node, "smoke_test_node", "", &context, &node_options));

  const rosidl_message_type_support_t * ts =
    ROSIDL_GET_MSG_TYPE_SUPPORT(builtin_interfaces, msg, Time);

  rcl_publisher_options_t pub_options = rcl_publisher_get_default_options();
  rcl_publisher_t publisher = rcl_get_zero_initialized_publisher();
  CHECK_RCL(rcl_publisher_init(&publisher, &node, ts, "/smoke_test_chatter", &pub_options));

  rcl_subscription_options_t sub_options = rcl_subscription_get_default_options();
  rcl_subscription_t subscription = rcl_get_zero_initialized_subscription();
  CHECK_RCL(
    rcl_subscription_init(&subscription, &node, ts, "/smoke_test_chatter", &sub_options));

  // Give discovery a moment (needed for some RMW implementations even in-process).
  for (int i = 0; i < 50; ++i) {
    size_t count = 0;
    if (rcl_publisher_get_subscription_count(&publisher, &count) != RCL_RET_OK) {
      rcl_reset_error();
    }
    if (count > 0) {
      break;
    }
    struct timespec ts_req = {0, 100 * 1000 * 1000};
    nanosleep(&ts_req, NULL);
  }

  builtin_interfaces__msg__Time msg_out;
  builtin_interfaces__msg__Time__init(&msg_out);
  msg_out.sec = 42;
  msg_out.nanosec = 12345;

  int received = 0;
  builtin_interfaces__msg__Time msg_in;
  builtin_interfaces__msg__Time__init(&msg_in);

  for (int attempt = 0; attempt < 20 && !received; ++attempt) {
    CHECK_RCL(rcl_publish(&publisher, &msg_out, NULL));

    rcl_wait_set_t wait_set = rcl_get_zero_initialized_wait_set();
    CHECK_RCL(rcl_wait_set_init(&wait_set, 1, 0, 0, 0, 0, 0, &context, rcl_get_default_allocator()));
    CHECK_RCL(rcl_wait_set_clear(&wait_set));
    size_t index = 0;
    CHECK_RCL(rcl_wait_set_add_subscription(&wait_set, &subscription, &index));

    ret = rcl_wait(&wait_set, RCL_MS_TO_NS(500));
    if (ret == RCL_RET_OK && wait_set.subscriptions[index] != NULL) {
      rcl_ret_t take_ret = rcl_take(&subscription, &msg_in, NULL, NULL);
      if (take_ret == RCL_RET_OK) {
        received = 1;
      } else {
        rcl_reset_error();
      }
    } else if (ret == RCL_RET_TIMEOUT) {
      rcl_reset_error();
    } else {
      fprintf(stderr, "rcl_wait failed: %s\n", rcl_get_error_string().str);
      rcl_reset_error();
    }
    CHECK_RCL(rcl_wait_set_fini(&wait_set));
  }

  int status = 0;
  if (!received) {
    fprintf(stderr, "FAIL: never received published message\n");
    status = 1;
  } else if (msg_in.sec != msg_out.sec || msg_in.nanosec != msg_out.nanosec) {
    fprintf(
      stderr, "FAIL: received message mismatch (sec=%d nanosec=%u)\n",
      msg_in.sec, msg_in.nanosec);
    status = 1;
  } else {
    printf(
      "PASS: received Time{sec=%d, nanosec=%u} via RMW_IMPLEMENTATION=%s\n",
      msg_in.sec, msg_in.nanosec, getenv("RMW_IMPLEMENTATION") ? getenv("RMW_IMPLEMENTATION") : "(default)");
  }

  builtin_interfaces__msg__Time__fini(&msg_out);
  builtin_interfaces__msg__Time__fini(&msg_in);

  rcl_ret_t fini_ret;
  fini_ret = rcl_subscription_fini(&subscription, &node);
  if (fini_ret != RCL_RET_OK) { status = 1; }
  fini_ret = rcl_publisher_fini(&publisher, &node);
  if (fini_ret != RCL_RET_OK) { status = 1; }
  fini_ret = rcl_node_fini(&node);
  if (fini_ret != RCL_RET_OK) { status = 1; }
  fini_ret = rcl_shutdown(&context);
  if (fini_ret != RCL_RET_OK) { status = 1; }
  fini_ret = rcl_context_fini(&context);
  if (fini_ret != RCL_RET_OK) { status = 1; }
  if (rcl_init_options_fini(&init_options) != RCL_RET_OK) { status = 1; }

  return status;
}
