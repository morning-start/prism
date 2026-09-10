import {
  "morning-start/prism/sdk",
  "morning-start/prism/provider/openai",
  "morning-start/prism/provider/responses",
  "morning-start/prism/provider/messages",
  "morning-start/prism/provider/gemini",
}

pub fn main() -> Unit {
  let providers = @sdk.build_providers()
  assert_eq(providers.length(), 4)

  let openai_reg = providers[0]
  assert_eq(openai_reg.name, @openai.metadata().name())
  assert_eq(openai_reg.model_pattern, @openai.metadata().model_pattern())

  let responses_reg = providers[1]
  assert_eq(responses_reg.name, @responses.metadata().name())

  let messages_reg = providers[2]
  assert_eq(messages_reg.name, @messages.metadata().name())

  let gemini_reg = providers[3]
  assert_eq(gemini_reg.name, @gemini.metadata().name())
}
