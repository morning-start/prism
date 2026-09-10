import {
  "morning-start/prism/provider/meta",
  "morning-start/prism/provider/openai",
  "morning-start/prism/provider/responses",
  "morning-start/prism/provider/messages",
  "morning-start/prism/provider/gemini",
}

pub fn build_providers() -> Array[ProviderRegistration] {
  let openai_meta = @openai.metadata()
  let responses_meta = @responses.metadata()
  let messages_meta = @messages.metadata()
  let gemini_meta = @gemini.metadata()

  let registrations = []

  // OpenAI
  registrations.push(
    ProviderRegistration::from_metadata(
      openai_meta,
      @openai.openai_to_lux_request,
      @openai.lux_request_to_openai,
      @openai.openai_to_lux_response,
      @openai.lux_response_to_openai,
      @openai.openai_sse_to_events,
      @openai.lux_events_to_openai_sse,
    )
  )

  // Responses
  registrations.push(
    ProviderRegistration::from_metadata(
      responses_meta,
      @responses.openai_to_lux_request,
      @responses.lux_request_to_openai,
      @responses.openai_to_lux_response,
      @responses.lux_response_to_openai,
      @responses.openai_sse_to_events,
      @responses.lux_events_to_openai_sse,
    )
  )

  // Messages (Anthropic)
  registrations.push(
    ProviderRegistration::from_metadata(
      messages_meta,
      @messages.messages_to_lux_request,
      @messages.lux_request_to_messages,
      @messages.messages_to_lux_response,
      @messages.lux_response_to_messages,
      @messages.messages_sse_to_events,
      @messages.lux_events_to_messages_sse,
    )
  )

  // Gemini
  registrations.push(
    ProviderRegistration::from_metadata(
      gemini_meta,
      @gemini.gemini_to_lux_request,
      @gemini.lux_request_to_gemini,
      @gemini.gemini_to_lux_response,
      @gemini.lux_response_to_gemini,
      @gemini.gemini_sse_to_events,
      @gemini.lux_events_to_gemini_sse,
    )
  )

  registrations
}
